import client.{type Client}
import envoy
import exception
import gleam/bit_array
import gleam/erlang/process
import gleam/http/request
import gleam/otp/actor
import gleam/otp/static_supervisor.{type Supervisor}
import gleam/otp/supervision
import gleam/time/duration
import gleam/time/timestamp
import global_value
import group_registry
import mist
import pog
import server
import server/auth
import server/board
import server/database
import server/realtime
import server/user.{type User}
import youid/uuid.{type Uuid}

pub fn with_connection(test_case: fn(pog.Connection) -> a) -> Nil {
  let pool = global_connection_pool()
  let assert Error(pog.TransactionRolledBack(Nil)) =
    pog.transaction(pool, fn(conn) {
      test_case(conn)
      Error(Nil)
    })
  Nil
}

pub fn using_server(test_case: fn() -> Nil) -> Nil {
  let pool = global_connection_pool()
  let registry_name = process.new_name("registry")
  let broker_name = process.new_name("broker")
  let board_name = process.new_name("board")

  let assert Ok(actor.Started(pid: server, ..)) =
    init_server(registry_name, broker_name, board_name)
  use <- exception.defer(fn() {
    server.stop(server)
    database.truncate_all(pool)
  })

  test_case()
}

pub fn using_client(test_case: fn(Client) -> a) -> Nil {
  use _, _, session_token <- using_user

  let assert Ok(request) = request.to("http://localhost:8000/api/ws")

  let encoded_token = {
    let token_string = uuid.to_string(session_token)
    // encodes the UUID string itself not the raw bytes
    bit_array.base64_encode(<<token_string:utf8>>, False)
  }
  let request =
    request.prepend_header(request, "cookie", "session=" <> encoded_token)

  let assert Ok(client) = client.init(request)
  use <- exception.defer(fn() { client.close(client) })

  test_case(client)
  Nil
}

pub fn with_user(test_case: fn(pog.Connection, User, Uuid) -> a) -> Nil {
  use conn <- with_connection

  let id = uuid.v4() |> uuid.to_string
  let email = "user_" <> id <> "@test.com"
  let username = "user_" <> id

  let assert Ok(#(user, session_token)) =
    auth.signup(
      conn,
      email:,
      username:,
      password: "password1",
      session_expires_in: duration.seconds(10_000_000),
      now: timestamp.system_time(),
    )
  test_case(conn, user, session_token)
  Nil
}

pub fn using_user(test_case: fn(pog.Connection, User, Uuid) -> a) -> Nil {
  let pool = global_connection_pool()

  let id = uuid.v4() |> uuid.to_string
  let email = "user_" <> id <> "@test.com"
  let username = "user_" <> id

  let assert Ok(#(user, session_token)) =
    auth.signup(
      pool,
      email:,
      username:,
      password: "password1",
      session_expires_in: duration.seconds(10_000_000),
      now: timestamp.system_time(),
    )
  test_case(pool, user, session_token)
  Nil
}

fn init_server(
  registry_name: process.Name(group_registry.Message(realtime.WebSocketMessage)),
  broker_name: process.Name(realtime.BrokerMessage),
  board_name: process.Name(board.Message),
) -> Result(actor.Started(Supervisor), actor.StartError) {
  let pool = global_connection_pool()

  let board_subject = process.named_subject(board_name)

  let registry = group_registry.get_registry(registry_name)

  let broker_config = realtime.broker_config(broker_name, registry)
  let broker = process.named_subject(broker_name)

  let mist_config =
    server.mist_config(pool, board_subject, broker, registry)
    |> mist.after_start(fn(_, _, _) { Nil })

  let registry_spec = registry_name |> group_registry.supervised
  let broker_spec = supervision.worker(fn() { actor.start(broker_config) })
  let board_spec = board.supervised(board_name, pool, 50, 50)
  let server_spec = mist.supervised(mist_config)

  static_supervisor.new(static_supervisor.RestForOne)
  |> static_supervisor.add(registry_spec)
  |> static_supervisor.add(broker_spec)
  |> static_supervisor.add(board_spec)
  |> static_supervisor.add(server_spec)
  |> static_supervisor.start()
}

/// safe to create name "dynamically" since callback is only ran once
fn global_connection_pool() -> pog.Connection {
  global_value.create_with_unique_name(
    "server_test.global_connection_pool",
    fn() {
      let name = process.new_name("db")
      let assert Ok(database_url) = envoy.get("TEST_DATABASE_URL")
      let config = server.pog_config(name, database_url)
      let assert Ok(_) = pog.start(config)
      pog.named_connection(config.pool_name)
    },
  )
}
