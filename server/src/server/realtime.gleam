import atomic_array.{type AtomicArray}
import gleam/erlang/process
import gleam/http/request
import gleam/http/response
import gleam/int
import gleam/json
import gleam/list
import gleam/option.{Some}
import gleam/otp/actor
import gleam/set.{type Set}
import group_registry.{type GroupRegistry}
import mist
import shared/transport.{type ClientMessage, type ServerMessage}
import wisp

pub fn websocket_handler(
  request: request.Request(mist.Connection),
  broker: process.Subject(BrokerMessage),
  registry: GroupRegistry(WebsocketMessage),
  board: AtomicArray,
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

type WebsocketState {
  WebsocketState(
    broker: process.Subject(BrokerMessage),
    registry: GroupRegistry(WebsocketMessage),
    board: AtomicArray,
  )
}

fn init_websocket(
  _conn: mist.WebsocketConnection,
  broker: process.Subject(BrokerMessage),
  registry: GroupRegistry(WebsocketMessage),
  board: AtomicArray,
) -> #(WebsocketState, process.Subject(WebsocketMessage)) {
  let client = group_registry.join(registry, "board", process.self())
  process.send(broker, ClientJoined)
  #(WebsocketState(broker:, registry:, board:), client)
}

fn close_websocket(state: WebsocketState) -> Nil {
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
  TileUpdated(x: Int, y: Int, color: Int)
}

fn handle_websocket_message(
  state: WebsocketState,
  message: mist.WebsocketMessage(WebsocketMessage),
  conn: mist.WebsocketConnection,
) -> mist.Next(WebsocketState, WebsocketMessage) {
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
  state: WebsocketState,
  message: ClientMessage,
) -> WebsocketState {
  case message {
    transport.TileChanged(x:, y:, color:) -> {
      let tile_index = y * 1000 + x
      let array_index = tile_index / 16
      let bit_offset = { tile_index % 16 } * 4

      let assert Ok(packed_colors) = atomic_array.get(state.board, array_index)
      let assert <<left:size(bit_offset), _:4, right:bits>> = <<
        packed_colors:64,
      >>
      let assert <<packed_colors:64>> = <<
        left:size(bit_offset),
        color:4,
        right:bits,
      >>
      let assert Ok(_) =
        atomic_array.exchange(
          state.board,
          at: array_index,
          replace_with: packed_colors,
        )

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
    |> transport.server_message_to_json
    |> json.to_string
    |> mist.send_text_frame(conn, _)

  case result {
    Ok(Nil) -> Nil
    Error(_) -> wisp.log_error("failed to send websocket frame to client")
  }
}
