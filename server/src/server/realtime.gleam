import gleam/erlang/process
import gleam/http/request
import gleam/http/response
import gleam/int
import gleam/list
import gleam/option.{Some}
import gleam/otp/actor
import gleam/set.{type Set}
import group_registry.{type GroupRegistry}
import mist

pub fn websocket_handler(
  request: request.Request(mist.Connection),
  broker: process.Subject(BrokerMessage),
  registry: GroupRegistry(WebsocketMessage),
) -> response.Response(mist.ResponseData) {
  mist.websocket(
    request,
    handler: handle_websocket_message,
    on_init: fn(conn) {
      let #(state, client) = init_websocket(conn, broker, registry)
      let selector = process.new_selector() |> process.select(client)
      #(state, Some(selector))
    },
    on_close: close_websocket,
  )
}

/// messages sent to Broker
pub opaque type BrokerMessage {
  ClientConnected
  ClientDisconnected
}

pub fn broker_config(
  name: process.Name(BrokerMessage),
  registry: GroupRegistry(WebsocketMessage),
) -> actor.Builder(Nil, BrokerMessage, process.Subject(BrokerMessage)) {
  actor.new(Nil)
  |> actor.on_message(fn(state, message) {
    handle_broker_message(state, message, registry)
  })
  |> actor.named(name)
}

fn handle_broker_message(
  state: Nil,
  message: BrokerMessage,
  registry: GroupRegistry(WebsocketMessage),
) -> actor.Next(Nil, BrokerMessage) {
  case message {
    ClientConnected -> {
      let clients = group_registry.members(registry, "board")
      let user_count = list.length(clients)

      clients
      |> list.each(fn(client) {
        process.send(client, UserCountChanged(user_count:))
      })

      actor.continue(state)
    }
    ClientDisconnected -> {
      let clients = group_registry.members(registry, "board")
      let user_count = list.length(clients)

      clients
      |> list.each(fn(client) {
        process.send(client, UserCountChanged(user_count:))
      })

      actor.continue(state)
    }
  }
}

fn publish(
  registry: GroupRegistry(WebsocketMessage),
  message: WebsocketMessage,
) -> Nil {
  let clients = group_registry.members(registry, "board")

  clients
  |> list.each(fn(client) { process.send(client, message) })
}

/// messages sent to websocket process by Broker
pub opaque type WebsocketMessage {
  UserCountChanged(user_count: Int)
}

type WebsocketState {
  WebsocketState(
    broker: process.Subject(BrokerMessage),
    registry: GroupRegistry(WebsocketMessage),
  )
}

fn handle_websocket_message(
  state: WebsocketState,
  message: mist.WebsocketMessage(WebsocketMessage),
  conn: mist.WebsocketConnection,
) -> mist.Next(WebsocketState, WebsocketMessage) {
  case message {
    // sent by client
    mist.Text(_) -> todo
    // sent by broker
    mist.Custom(message) ->
      case message {
        UserCountChanged(user_count:) -> {
          let assert Ok(_) =
            mist.send_text_frame(conn, int.to_string(user_count))
            as "failed to send websocket frame to client"
          mist.continue(state)
        }
      }
    mist.Binary(_) -> mist.continue(state)
    mist.Closed | mist.Shutdown -> mist.stop()
  }
}

fn init_websocket(
  _conn: mist.WebsocketConnection,
  broker: process.Subject(BrokerMessage),
  registry: GroupRegistry(WebsocketMessage),
) -> #(WebsocketState, process.Subject(WebsocketMessage)) {
  let client = group_registry.join(registry, "board", process.self())
  process.send(broker, ClientConnected)
  #(WebsocketState(broker:, registry:), client)
}

fn close_websocket(state: WebsocketState) -> Nil {
  echo "connection severed!"
  group_registry.leave(state.registry, "board", [process.self()])
  process.send(state.broker, ClientDisconnected)
  Nil
}
