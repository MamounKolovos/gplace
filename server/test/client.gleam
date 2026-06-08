import collie
import gleam/erlang/process.{type Pid, type Subject}
import gleam/http/request.{type Request}
import gleam/json
import gleam/otp/actor
import gleam/result
import logging
import shared/transport.{type ClientMessage, type ServerMessage}

// asserting everywhere since this is meant to be used by tests
// no real reason to let caller handle errors

// might change at some point in the future
// since it is technically "incorrect" api design

pub opaque type Client {
  Client(
    self: Pid,
    mailbox: Subject(collie.WebsocketMessage(Message)),
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

pub fn init(request: Request(String)) -> Result(Client, actor.StartError) {
  let inbox = process.new_subject()

  collie.new(request, State(client_inbox: inbox))
  |> collie.on_message(handle_message)
  |> collie.on_close(handle_close)
  |> collie.start
  |> result.map(fn(actor) {
    Client(self: actor.pid, mailbox: actor.data, inbox:)
  })
}

fn handle_close(_state: State, _reason: collie.CloseReason) -> Nil {
  Nil
}

fn handle_message(
  conn: collie.Connection,
  state: State,
  message: collie.Message(Message),
) -> collie.Next(State, Message) {
  case message {
    collie.Text(message) ->
      case json.parse(message, transport.server_message_decoder()) {
        Ok(message) -> {
          process.send(state.client_inbox, message)
          collie.continue(state)
        }
        Error(_) -> {
          logging.log(
            logging.Warning,
            "failed to parse server message into valid json",
          )
          collie.continue(state)
        }
      }
    collie.Binary(_) -> {
      logging.log(logging.Error, "expected string not binary")
      collie.send_close_frame(conn, collie.UnsupportedData(<<>>))
    }
    collie.User(message) ->
      case message {
        Send(message) -> {
          let assert Ok(_) = send_to_server(conn, message)
          collie.continue(state)
        }
        Close -> {
          collie.send_close_frame(conn, collie.NormalClosure(<<>>))
        }
      }
  }
}

fn send_to_server(
  conn: collie.Connection,
  message: ClientMessage,
) -> Result(Nil, collie.SocketReason) {
  message
  |> transport.encode_client_message
  |> collie.send_text_frame(conn, _)
}

pub fn send(client: Client, message: ClientMessage) -> Nil {
  process.send(client.mailbox, Send(message) |> collie.to_user_message)
}

pub fn close(client: Client) -> Nil {
  process.send(client.mailbox, collie.to_user_message(Close))

  let _ = process.monitor(client.self)
  let reply_with = process.new_subject()

  let selector =
    process.new_selector()
    |> process.select(reply_with)
    |> process.select_monitors(fn(_) { Nil })

  let assert Ok(_) = process.selector_receive(selector, within: 1000)

  Nil
}

pub fn receive(client: Client) -> Result(ServerMessage, Nil) {
  process.receive(client.inbox, within: 1000)
}
