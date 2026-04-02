import gleam/bit_array
import gleam/erlang/process
import gleam/http/request
import gleam/http/response
import gleam/json
import gleam/list
import gleam/option.{type Option, None, Some}
import gleam/order
import gleam/otp/actor
import gleam/result
import gleam/time/duration.{type Duration}
import gleam/time/timestamp.{type Timestamp}
import group_registry.{type GroupRegistry}
import mist
import pog
import server/auth
import server/board.{type Board}
import server/user.{type User}
import shared/transport.{type ClientMessage, type ServerMessage}
import wisp
import youid/uuid

pub fn websocket_handler(
  request: request.Request(mist.Connection),
  db: pog.Connection,
  broker: process.Subject(BrokerMessage),
  registry: GroupRegistry(WebSocketMessage),
  board: Board,
  tile_cooldown: Duration,
) -> response.Response(mist.ResponseData) {
  // must be done here instead of on_init since we still have the request here
  let user = get_user(request, db) |> option.from_result

  let last_placed_at = case user {
    Some(user) ->
      user.get_last_placed_at(user, db) |> option.from_result |> option.flatten
    None -> None
  }

  mist.websocket(
    request,
    handler: fn(state, message, conn) {
      handle_websocket_message(state, message, conn, tile_cooldown)
    },
    on_init: fn(conn) {
      let #(state, client) =
        init_websocket(conn, user, broker, registry, board, last_placed_at)
      let selector = process.new_selector() |> process.select(client)
      #(state, Some(selector))
    },
    on_close: close_websocket,
  )
}

fn get_user(
  request: request.Request(mist.Connection),
  db: pog.Connection,
) -> Result(User, Nil) {
  use session_token <- result.try(
    request.get_cookies(request)
    |> list.key_find("session")
    |> result.try(bit_array.base64_decode)
    |> result.try(bit_array.to_string)
    |> result.try(uuid.from_string),
  )

  auth.authenticate(
    db,
    session_token: session_token,
    now: timestamp.system_time(),
  )
  |> result.replace_error(Nil)
}

type WebSocketState {
  WebSocketState(
    user: Option(User),
    broker: process.Subject(BrokerMessage),
    registry: GroupRegistry(WebSocketMessage),
    board: Board,
    /// `None` could either mean the user doesn't exist or that they haven't placed a tile yet
    last_placed_at: Option(Timestamp),
  )
}

fn init_websocket(
  _conn: mist.WebsocketConnection,
  user: Option(User),
  broker: process.Subject(BrokerMessage),
  registry: GroupRegistry(WebSocketMessage),
  board: Board,
  last_placed_at: Option(Timestamp),
) -> #(WebSocketState, process.Subject(WebSocketMessage)) {
  let client = group_registry.join(registry, "board", process.self())
  process.send(broker, ClientJoined)
  #(WebSocketState(user:, broker:, registry:, board:, last_placed_at:), client)
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
  tile_cooldown: Duration,
) -> mist.Next(WebSocketState, WebSocketMessage) {
  case message {
    // sent by client
    mist.Text(message) ->
      case json.parse(message, transport.client_message_decoder()) {
        Ok(message) -> handle_client_message(state, message, tile_cooldown)
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
  tile_cooldown: Duration,
) -> mist.Next(WebSocketState, WebSocketMessage) {
  case state.user, message {
    Some(user), transport.TileChanged(x:, y:, color:) -> {
      let now = timestamp.system_time()

      let on_cooldown = case state.last_placed_at {
        Some(last_placed_at) -> {
          let elapsed = timestamp.difference(last_placed_at, now)
          duration.compare(elapsed, tile_cooldown) == order.Lt
        }
        None -> False
      }

      case on_cooldown {
        //TODO: silently ignore for now, but might want to close connection in the future
        // since the user would have to modify the JS to bypass the client cooldown
        True -> mist.continue(state)
        False ->
          // authoritative server, ideally client should never send messages for out of bounds tiles
          case
            board.set_tile(
              state.board,
              user,
              x:,
              y:,
              color:,
              now: timestamp.system_time(),
            )
          {
            Ok(_) -> {
              process.send(state.broker, TileChanged(x:, y:, color:))
              let state = WebSocketState(..state, last_placed_at: Some(now))
              mist.continue(state)
            }
            Error(_) -> mist.stop()
          }
      }
    }

    // TODO: should probably log something here
    _, _ -> mist.continue(state)
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
