import envoy
import gleam/erlang/process
import gleam/http/request
import gleam/otp/actor
import gleam/otp/static_supervisor
import gleam/otp/supervision
import gleam/result
import gleam/time/duration
import gleam/time/timestamp
import group_registry.{type GroupRegistry}
import mist
import pog
import server/auth
import server/board
import server/realtime
import server/router
import server/web.{Context}
import wisp
import wisp/wisp_mist

pub fn main() -> Nil {
  wisp.configure_logger()

  let pool_name = process.new_name("db")
  let registry_name = process.new_name("registry")
  let broker_name = process.new_name("broker")
  let board_name = process.new_name("board")

  let assert Ok(_) = init(pool_name, registry_name, broker_name, board_name)
    as "server could not be started"

  let pool = pog.named_connection(pool_name)

  // will error every subsequent run but it's fine for now
  let _ = seed(pool)

  process.sleep_forever()
}

pub fn init(
  pool_name: process.Name(pog.Message),
  registry_name: process.Name(group_registry.Message(realtime.WebSocketMessage)),
  broker_name: process.Name(realtime.BrokerMessage),
  board_name: process.Name(board.Message),
) -> Result(Nil, actor.StartError) {
  let assert Ok(database_url) = envoy.get("DATABASE_URL")
  let pog_config = pog_config(pool_name, database_url)
  let pool = pog.named_connection(pog_config.pool_name)

  let board_subject = process.named_subject(board_name)

  let registry = group_registry.get_registry(registry_name)

  let broker_config = realtime.broker_config(broker_name, registry)
  let broker = process.named_subject(broker_name)

  let mist_config = mist_config(pool, board_subject, broker, registry)

  let db_spec = pog_config |> pog.supervised
  let registry_spec = registry_name |> group_registry.supervised
  let broker_spec = supervision.worker(fn() { actor.start(broker_config) })
  let board_spec = board.supervised(board_name, pool, 300, 300)
  let server_spec = mist.supervised(mist_config)

  let supervisor =
    static_supervisor.new(static_supervisor.RestForOne)
    |> static_supervisor.add(db_spec)
    |> static_supervisor.add(registry_spec)
    |> static_supervisor.add(broker_spec)
    |> static_supervisor.add(board_spec)
    |> static_supervisor.add(server_spec)
    |> static_supervisor.start()

  // don't need to leak supervisor reference to caller
  result.replace(supervisor, Nil)
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
  board_subject: process.Subject(board.Message),
  broker: process.Subject(realtime.BrokerMessage),
  registry: GroupRegistry(realtime.WebSocketMessage),
) -> mist.Builder(mist.Connection, mist.ResponseData) {
  let assert Ok(secret_key_base) = envoy.get("SECRET_KEY_BASE")
  let ctx = Context(db: pool)

  mist.new(fn(request) {
    let board = board.get(board_subject)

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

pub fn pog_config(
  name: process.Name(pog.Message),
  database_url: String,
) -> pog.Config {
  let assert Ok(pog_config) = pog.url_config(name, database_url)
  pog_config |> pog.pool_size(10)
}

pub fn seed(db: pog.Connection) {
  auth.signup(
    db,
    email: "admin@gmail.com",
    username: "admin",
    password: "password1",
    session_expires_in: duration.seconds(10_000_000),
    now: timestamp.system_time(),
  )
}
