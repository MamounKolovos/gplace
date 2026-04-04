import client.{type Client}
import envoy
import exception
import gleam/erlang/process
import gleam/http
import gleam/http/request
import gleam/http/response
import gleam/list
import gleam/otp/actor
import gleam/otp/static_supervisor.{type Supervisor}
import gleam/otp/supervision
import gleam/time/duration.{type Duration}
import gleam/time/timestamp
import global_value
import group_registry.{type GroupRegistry}
import mist
import pog
import server
import server/auth
import server/board
import server/database
import server/realtime
import server/user.{type User}
import server/web
import wisp
import wisp/simulate
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

pub fn default_server_config() -> server.Config {
  server.Config(
    board_width: 50,
    board_height: 50,
    tile_cooldown: duration.seconds(5),
    session_duration: duration.hours(100),
  )
}

pub fn using_server(
  config: server.Config,
  test_case: fn(fn(wisp.Request) -> wisp.Response) -> Nil,
) -> Nil {
  let registry_name = process.new_name("registry")
  let broker_name = process.new_name("broker")
  let board_name = process.new_name("board")

  let pool = global_connection_pool()

  let board_subject = process.named_subject(board_name)

  let registry = group_registry.get_registry(registry_name)

  let broker_config = realtime.broker_config(broker_name, registry)
  let broker = process.named_subject(broker_name)

  let ctx = web.Context(db: pool, session_duration: config.session_duration)

  let wisp_handler = server.wisp_handler(ctx, board_subject)
  let mist_config =
    server.mist_config(
      wisp_handler,
      ctx,
      board_subject,
      broker,
      registry,
      config.tile_cooldown,
    )
    |> mist.after_start(fn(_, _, _) { Nil })

  let registry_spec = registry_name |> group_registry.supervised
  let broker_spec = supervision.worker(fn() { actor.start(broker_config) })
  let board_spec =
    board.supervised(board_name, pool, config.board_width, config.board_height)
  let server_spec = mist.supervised(mist_config)

  let assert Ok(actor.Started(pid: server, ..)) =
    static_supervisor.new(static_supervisor.RestForOne)
    |> static_supervisor.add(registry_spec)
    |> static_supervisor.add(broker_spec)
    |> static_supervisor.add(board_spec)
    |> static_supervisor.add(server_spec)
    |> static_supervisor.start()

  use <- exception.defer(fn() {
    server.stop(server)
    database.truncate_all(pool)
  })

  test_case(wisp_handler)
}

pub fn using_client(
  request_handler: fn(wisp.Request) -> wisp.Response,
  test_case: fn(Client) -> a,
) -> Nil {
  let id = uuid.v4() |> uuid.to_string
  let email = "user_" <> id <> "@test.com"
  let username = "user_" <> id

  let query = [
    #("email", email),
    #("username", username),
    #("password", "password1"),
  ]

  let signup_request =
    simulate.browser_request(http.Post, "/api/signup")
    |> simulate.form_body(query)

  let signup_response = request_handler(signup_request)

  let assert Ok(session_token) =
    response.get_cookies(signup_response) |> list.key_find("session")

  let assert Ok(request) = request.to("http://localhost:8000/api/ws")
  let request =
    request.prepend_header(request, "cookie", "session=" <> session_token)

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
