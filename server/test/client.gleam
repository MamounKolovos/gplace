import gleam/erlang/process.{type Pid, type Subject}
import gleam/http/request
import gleam/json
import gleam/result
import shared/transport.{type ClientMessage, type ServerMessage}
import stratus

// asserting everywhere since this is meant to be used by tests
// no real reason to let caller handle errors

// might change at some point in the future
// since it is technically "incorrect" api design

pub opaque type Client {
  Client(
    self: Pid,
    mailbox: Subject(stratus.InternalMessage(Message)),
    inbox: Subject(ServerMessage),
  )
}

pub opaque type Message {
  Send(ClientMessage)
  Close
}

type State {
  State(client_inbox: Subject(ServerMessage))
}

pub fn init() -> Result(Client, stratus.InitializationError) {
  let assert Ok(request) = request.to("http://localhost:8000/api/ws")
  let inbox = process.new_subject()

  stratus.new(request, State(client_inbox: inbox))
  |> stratus.on_message(handle_message)
  |> stratus.on_close(handle_close)
  |> stratus.start
  |> result.map(fn(actor) {
    Client(self: actor.pid, mailbox: actor.data, inbox:)
  })
}

fn handle_close(_state: State, _reason: stratus.CloseReason) -> Nil {
  Nil
}

fn handle_message(
  state: State,
  message: stratus.Message(Message),
  conn: stratus.Connection,
) -> stratus.Next(State, Message) {
  case message {
    stratus.Text(message) ->
      case json.parse(message, transport.server_message_decoder()) {
        Ok(message) -> {
          process.send(state.client_inbox, message)
          stratus.continue(state)
        }
        Error(_) -> {
          let assert Ok(_) =
            stratus.close(conn, because: stratus.ProtocolError(<<>>))
          stratus.stop_abnormal(
            "failed to parse server message into valid json",
          )
        }
      }
    stratus.Binary(_) -> {
      let assert Ok(_) =
        stratus.close(conn, because: stratus.UnexpectedDataType(<<>>))
      stratus.stop_abnormal("expected string not bitarray")
    }
    stratus.User(message) ->
      case message {
        Send(message) -> {
          let assert Ok(_) = send_to_server(conn, message)
          stratus.continue(state)
        }
        Close -> {
          let assert Ok(_) = stratus.close(conn, because: stratus.Normal(<<>>))
          stratus.stop()
        }
      }
  }
}

fn send_to_server(
  conn: stratus.Connection,
  message: ClientMessage,
) -> Result(Nil, stratus.SocketReason) {
  message
  |> transport.encode_client_message
  |> stratus.send_text_message(conn, _)
}

pub fn send(client: Client, message: ClientMessage) -> Nil {
  process.send(client.mailbox, message |> Send |> stratus.to_user_message)
}

pub fn close(client: Client) -> Nil {
  process.send(client.mailbox, stratus.to_user_message(Close))

  let _ = process.monitor(client.self)
  let reply_with = process.new_subject()

  let selector =
    process.new_selector()
    |> process.select(reply_with)
    |> process.select_monitors(fn(_) { Nil })

  let assert Ok(_) = process.selector_receive(selector, within: 1000)

  Nil
}

pub fn receive(client: Client) -> ServerMessage {
  let assert Ok(message) = process.receive(client.inbox, within: 1000)
  message
}
