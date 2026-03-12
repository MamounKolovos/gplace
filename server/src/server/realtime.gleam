import gleam/erlang/process
import gleam/http/request
import gleam/http/response
import gleam/json
import gleam/list
import gleam/option.{Some}
import gleam/otp/actor
import group_registry.{type GroupRegistry}
import mist
import server/board.{type Board}
import shared/transport.{type ClientMessage, type ServerMessage}
import wisp

pub fn websocket_handler(
  request: request.Request(mist.Connection),
  broker: process.Subject(BrokerMessage),
  registry: GroupRegistry(WebSocketMessage),
  board: Board,
) -> response.Response(mist.ResponseData) {
  mist.websocket(
    request,
    handler: handle_websocket_message,
    on_init: fn(conn) {
      let #(state, client) = init_websocket(conn, broker, registry, board)
      let selector = process.new_selector() |> process.select(client)
      #(state, Some(selector))
    },
    on_close: close_websocket,
  )
}

type WebSocketState {
  WebSocketState(
    broker: process.Subject(BrokerMessage),
    registry: GroupRegistry(WebSocketMessage),
    board: Board,
  )
}

fn init_websocket(
  _conn: mist.WebsocketConnection,
  broker: process.Subject(BrokerMessage),
  registry: GroupRegistry(WebSocketMessage),
  board: Board,
) -> #(WebSocketState, process.Subject(WebSocketMessage)) {
  let client = group_registry.join(registry, "board", process.self())
  process.send(broker, ClientJoined)
  #(WebSocketState(broker:, registry:, board:), client)
}

fn close_websocket(state: WebSocketState) -> Nil {
  echo "connection severed!"
  group_registry.leave(state.registry, "board", [process.self()])
  process.send(state.broker, ClientLeft)
  Nil
}

/// messages sent to Broker
pub opaque type BrokerMessage {
  ClientJoined
  ClientLeft
  TileChanged(x: Int, y: Int, color: Int)
}

pub fn broker_config(
  name: process.Name(BrokerMessage),
  registry: GroupRegistry(WebSocketMessage),
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
  registry: GroupRegistry(WebSocketMessage),
) -> actor.Next(Nil, BrokerMessage) {
  case message {
    ClientJoined -> {
      let clients = group_registry.members(registry, "board")
      let user_count = list.length(clients)

      clients
      |> list.each(fn(client) {
        process.send(client, UserCountChanged(user_count:))
      })

      actor.continue(state)
    }
    ClientLeft -> {
      let clients = group_registry.members(registry, "board")
      let user_count = list.length(clients)

      clients
      |> list.each(fn(client) {
        process.send(client, UserCountChanged(user_count:))
      })

      actor.continue(state)
    }
    TileChanged(x:, y:, color:) -> {
      broadcast(registry, TileUpdated(x:, y:, color:))
      actor.continue(state)
    }
  }
}

fn broadcast(
  registry: GroupRegistry(WebSocketMessage),
  message: WebSocketMessage,
) -> Nil {
  let clients = group_registry.members(registry, "board")

  clients
  |> list.each(fn(client) { process.send(client, message) })
}

/// messages sent to websocket process by Broker
pub opaque type WebSocketMessage {
  UserCountChanged(user_count: Int)
  TileUpdated(x: Int, y: Int, color: Int)
}

fn handle_websocket_message(
  state: WebSocketState,
  message: mist.WebsocketMessage(WebSocketMessage),
  conn: mist.WebsocketConnection,
) -> mist.Next(WebSocketState, WebSocketMessage) {
  case message {
    // sent by client
    mist.Text(message) ->
      case json.parse(message, transport.client_message_decoder()) {
        Ok(message) -> {
          let state = handle_client_message(state, message)
          mist.continue(state)
        }
        Error(_) -> {
          wisp.log_error("failed to parse client message")
          mist.stop()
        }
      }
    // sent by broker
    mist.Custom(message) ->
      case message {
        UserCountChanged(user_count:) -> {
          send_server_message(
            conn,
            transport.UserCountUpdated(count: user_count),
          )
          mist.continue(state)
        }
        TileUpdated(x:, y:, color:) -> {
          send_server_message(conn, transport.TileUpdate(x:, y:, color:))
          mist.continue(state)
        }
      }
    mist.Binary(_) -> mist.continue(state)
    mist.Closed | mist.Shutdown -> mist.stop()
  }
}

fn handle_client_message(
  state: WebSocketState,
  message: ClientMessage,
) -> WebSocketState {
  case message {
    transport.TileChanged(x:, y:, color:) -> {
      // authoritative server, ideally client should never send messages for out of bounds tiles
      let assert Ok(_) = board.set_tile(state.board, x: x, y: y, color: color)

      process.send(state.broker, TileChanged(x:, y:, color:))
      state
    }
  }
}

fn send_server_message(
  conn: mist.WebsocketConnection,
  message: ServerMessage,
) -> Nil {
  let result =
    message
    |> transport.encode_server_message
    |> mist.send_text_frame(conn, _)

  case result {
    Ok(Nil) -> Nil
    Error(_) -> wisp.log_error("failed to send websocket frame to client")
  }
}
