import envoy
import gleam/erlang/process
import gleam/http/request
import gleam/otp/actor
import gleam/otp/static_supervisor.{type Supervisor}
import gleam/otp/supervision
import group_registry.{type GroupRegistry}
import mist
import pog
import server/board_store.{type Board}
import server/realtime
import server/router
import server/web.{type Context, Context}
import wisp
import wisp/wisp_mist

pub fn main() -> Nil {
  wisp.configure_logger()

  let pool_name = process.new_name("db")
  let registry_name = process.new_name("registry")
  let broker_name = process.new_name("broker")

  let assert Ok(_) = init(pool_name, registry_name, broker_name)
    as "server could not be started"

  process.sleep_forever()
}

pub fn init(
  pool_name: process.Name(pog.Message),
  registry_name: process.Name(group_registry.Message(realtime.WebSocketMessage)),
  broker_name: process.Name(realtime.BrokerMessage),
) -> Result(actor.Started(Supervisor), actor.StartError) {
  let pog_config = pog_config(pool_name)
  let pool = pog.named_connection(pog_config.pool_name)

  let board = board_store.random(width: 1000, height: 1000)

  let registry = group_registry.get_registry(registry_name)

  let broker_config = realtime.broker_config(broker_name, registry)
  let broker = process.named_subject(broker_name)

  let mist_config = mist_config(pool, broker, registry, board)

  let db_spec = pog_config |> pog.supervised
  let registry_spec = registry_name |> group_registry.supervised
  let broker_spec = supervision.worker(fn() { actor.start(broker_config) })
  let server_spec =
    mist_config
    |> mist.supervised

  static_supervisor.new(static_supervisor.RestForOne)
  |> static_supervisor.add(db_spec)
  |> static_supervisor.add(registry_spec)
  |> static_supervisor.add(broker_spec)
  |> static_supervisor.add(server_spec)
  |> static_supervisor.start()
}

pub fn stop(server: process.Pid) -> Nil {
  process.send_exit(server)

  let _ = process.monitor(server)
  let reply_with = process.new_subject()

  let selector =
    process.new_selector()
    |> process.select(reply_with)
    |> process.select_monitors(fn(_) { Nil })

  let assert Ok(_) = process.selector_receive(selector, within: 1000)
  Nil
}

pub fn mist_config(
  pool: pog.Connection,
  broker: process.Subject(realtime.BrokerMessage),
  registry: GroupRegistry(realtime.WebSocketMessage),
  board: Board,
) -> mist.Builder(mist.Connection, mist.ResponseData) {
  let assert Ok(secret_key_base) = envoy.get("SECRET_KEY_BASE")
  let ctx = Context(db: pool)

  mist.new(fn(request) {
    case request.path_segments(request) {
      ["api", "ws"] ->
        realtime.websocket_handler(request, pool, broker, registry, board)
      _ -> {
        let handler = router.handle_request(_, ctx, board)
        wisp_mist.handler(handler, secret_key_base)(request)
      }
    }
  })
  |> mist.port(8000)
}

pub fn pog_config(name: process.Name(pog.Message)) -> pog.Config {
  let assert Ok(database_url) = envoy.get("DATABASE_URL")

  let assert Ok(pog_config) = pog.url_config(name, database_url)
  pog_config |> pog.pool_size(10)
}
