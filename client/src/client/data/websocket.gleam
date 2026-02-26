import lustre/effect.{type Effect}

pub type WebSocket

pub type Event {
  Opened(WebSocket)
  ReceivedMessage(String)
  Closed(code: Int)
}

pub fn init(url url: String, to_msg to_msg: fn(Event) -> msg) -> Effect(msg) {
  use dispatch <- effect.from

  do_init(
    url,
    on_open: fn(socket) { Opened(socket) |> to_msg |> dispatch },
    on_message: fn(data) { ReceivedMessage(data) |> to_msg |> dispatch },
    on_close: fn(code) { Closed(code:) |> to_msg |> dispatch },
  )
}

@external(javascript, "./websocket_ffi.mjs", "init")
fn do_init(
  url: String,
  on_open open: fn(WebSocket) -> Nil,
  on_message handle_message: fn(String) -> Nil,
  on_close close: fn(Int) -> Nil,
) -> Nil

pub fn send(socket: WebSocket, message: String) -> Effect(msg) {
  use _ <- effect.from

  do_send(socket, message)
}

@external(javascript, "./websocket_ffi.mjs", "send")
fn do_send(socket: WebSocket, message: String) -> Nil

pub fn close(socket: WebSocket) -> Effect(msg) {
  use _ <- effect.from

  do_close(socket)
}

@external(javascript, "./websocket_ffi.mjs", "close")
fn do_close(socket: WebSocket) -> Nil
