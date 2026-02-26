import envoy
import gleam/erlang/process
import gleam/http/request
import gleam/io
import gleam/option.{None, Some}
import gleam/otp/actor
import gleam/otp/static_supervisor.{type Supervisor}
import gleam/otp/supervision
import group_registry.{type GroupRegistry}
import mist
import pog
import server/realtime
import server/router
import server/web.{type Context, Context}
import wisp
import wisp/wisp_mist

pub fn main() -> Nil {
  wisp.configure_logger()

  let assert Ok(_) = init() as "server could not be started"

  process.sleep_forever()
}

pub fn init() -> Result(actor.Started(Supervisor), actor.StartError) {
  let pog_config = pog_config()
  let ctx = Context(db: pog.named_connection(pog_config.pool_name))

  let registry_name = process.new_name("registry")
  let registry = group_registry.get_registry(registry_name)

  let broker_name = process.new_name("broker")
  let broker_config = realtime.broker_config(broker_name, registry)
  let broker = process.named_subject(broker_name)

  let db_spec = pog_config |> pog.supervised
  let registry_spec = registry_name |> group_registry.supervised
  let broker_spec = supervision.worker(fn() { actor.start(broker_config) })
  let server_spec = mist_config(ctx, broker, registry) |> mist.supervised

  static_supervisor.new(static_supervisor.OneForOne)
  |> static_supervisor.add(db_spec)
  |> static_supervisor.add(registry_spec)
  |> static_supervisor.add(broker_spec)
  |> static_supervisor.add(server_spec)
  |> static_supervisor.start()
}

fn mist_config(
  ctx: Context,
  broker: process.Subject(realtime.BrokerMessage),
  registry: GroupRegistry(realtime.WebsocketMessage),
) -> mist.Builder(mist.Connection, mist.ResponseData) {
  let assert Ok(secret_key_base) = envoy.get("SECRET_KEY_BASE")

  mist.new(fn(request) {
    case request.path_segments(request) {
      ["api", "ws"] -> realtime.websocket_handler(request, broker, registry)
      _ -> {
        let handler = router.handle_request(_, ctx)
        wisp_mist.handler(handler, secret_key_base)(request)
      }
    }
  })
  |> mist.port(8000)
}

pub fn pog_config() -> pog.Config {
  let assert Ok(database_url) = envoy.get("DATABASE_URL")
  let pool_name = process.new_name("db")

  let assert Ok(pog_config) = pog.url_config(pool_name, database_url)
  pog_config |> pog.pool_size(10)
}
