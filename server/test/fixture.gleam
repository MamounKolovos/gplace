import client.{type Client}
import exception
import gleam/erlang/process
import gleam/otp/actor
import gleam/otp/static_supervisor.{type Supervisor}
import gleam/otp/supervision
import global_value
import group_registry
import mist
import pog
import server
import server/board
import server/realtime
import server/web.{Context}

pub fn with_connection(test_case: fn(pog.Connection) -> a) -> Nil {
  let pool = global_connection_pool()
  let assert Error(pog.TransactionRolledBack(Nil)) =
    pog.transaction(pool, fn(conn) {
      test_case(conn)
      Error(Nil)
    })
  Nil
}

pub fn with_server(test_case: fn() -> Nil) -> Nil {
  let registry_name = process.new_name("registry")
  let broker_name = process.new_name("broker")

  let assert Ok(actor.Started(pid: server, ..)) =
    init_server(registry_name, broker_name)
  use <- exception.defer(fn() { server.stop(server) })

  test_case()
}

pub fn with_client(test_case: fn(Client) -> a) -> Nil {
  let assert Ok(client) = client.init()
  use <- exception.defer(fn() { client.close(client) })

  test_case(client)
  Nil
}

fn init_server(
  registry_name: process.Name(group_registry.Message(realtime.WebSocketMessage)),
  broker_name: process.Name(realtime.BrokerMessage),
) -> Result(actor.Started(Supervisor), actor.StartError) {
  let ctx = Context(db: global_connection_pool())

  let board = board.random(width: 1000, height: 1000)

  let registry = group_registry.get_registry(registry_name)

  let broker_config = realtime.broker_config(broker_name, registry)
  let broker = process.named_subject(broker_name)

  let mist_config =
    server.mist_config(ctx, broker, registry, board)
    |> mist.after_start(fn(_, _, _) { Nil })

  let registry_spec = registry_name |> group_registry.supervised
  let broker_spec = supervision.worker(fn() { actor.start(broker_config) })
  let server_spec =
    mist_config
    |> mist.supervised

  static_supervisor.new(static_supervisor.RestForOne)
  |> static_supervisor.add(registry_spec)
  |> static_supervisor.add(broker_spec)
  |> static_supervisor.add(server_spec)
  |> static_supervisor.start()
}

/// safe to create name "dynamically" since callback is only ran once
fn global_connection_pool() -> pog.Connection {
  global_value.create_with_unique_name(
    "server_test.global_connection_pool",
    fn() {
      let name = process.new_name("db")
      let config = server.pog_config(name)
      let assert Ok(_) = pog.start(config)
      pog.named_connection(config.pool_name)
    },
  )
}
