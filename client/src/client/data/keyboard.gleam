//// TODO: maybe rename to keyboard.gleam depending on what else i add here

import gleam/dynamic/decode.{type Decoder, type Dynamic}
import lustre/effect.{type Effect}

pub type Code {
  Space
}

fn code_decoder() -> Decoder(Code) {
  use variant <- decode.then(decode.string)
  case variant {
    "Space" -> decode.success(Space)
    _ -> decode.failure(Space, "Code")
  }
}

pub type EventType {
  KeyDown
  KeyUp
}

fn event_type_to_string(type_: EventType) -> String {
  case type_ {
    KeyDown -> "keydown"
    KeyUp -> "keyup"
  }
}

pub type Event {
  Event(code: Code, repeat: Bool)
}

fn event_decoder() -> Decoder(Event) {
  use code <- decode.field("code", code_decoder())
  use repeat <- decode.field("repeat", decode.bool)
  decode.success(Event(code:, repeat:))
}

pub fn lifecycle(code code: Code, to_msg to_msg: fn(Bool) -> msg) -> Effect(msg) {
  use dispatch <- effect.from

  KeyDown
  |> event_type_to_string
  |> do_listen(fn(event) {
    case decode.run(event, event_decoder()) {
      Ok(event) if event.code == code && event.repeat == False ->
        to_msg(True) |> dispatch
      _ -> Nil
    }
  })

  KeyUp
  |> event_type_to_string
  |> do_listen(fn(event) {
    case decode.run(event, event_decoder()) {
      Ok(event) if event.code == code -> to_msg(False) |> dispatch
      _ -> Nil
    }
  })
}

pub fn listen(
  type_ type_: EventType,
  code code: Code,
  to_msg to_msg: fn(Event) -> msg,
) -> Effect(msg) {
  use dispatch <- effect.from

  use event <- do_listen(event_type_to_string(type_))
  case decode.run(event, event_decoder()) {
    Ok(event) if event.code == code -> event |> to_msg |> dispatch
    _ -> Nil
  }
}

@external(javascript, "./event_ffi.mjs", "listen")
fn do_listen(type_: String, listener: fn(Dynamic) -> Nil) -> Nil
