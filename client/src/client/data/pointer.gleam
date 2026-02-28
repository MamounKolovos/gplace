import gleam/dynamic/decode.{type Decoder, type Dynamic}
import lustre/effect.{type Effect}

pub type ButtonEventType {
  PointerDown
  PointerUp
}

fn button_event_type_to_string(type_: ButtonEventType) -> String {
  case type_ {
    PointerDown -> "pointerdown"
    PointerUp -> "pointerup"
  }
}

pub type MotionEventType {
  PointerMove
}

fn motion_event_type_to_string(type_: MotionEventType) -> String {
  case type_ {
    PointerMove -> "pointermove"
  }
}

pub type ButtonEvent {
  ButtonEvent(
    client_x: Float,
    client_y: Float,
    offset_x: Float,
    offset_y: Float,
    pointer_type: PointerType,
    button: Button,
  )
}

fn button_event_decoder() -> Decoder(ButtonEvent) {
  use client_x <- decode.field("clientX", decode.float)
  use client_y <- decode.field("clientY", decode.float)
  use offset_x <- decode.field("offsetX", decode.float)
  use offset_y <- decode.field("offsetY", decode.float)
  use pointer_type <- decode.field("pointerType", pointer_type_decoder())
  use button <- decode.field("button", button_decoder())
  decode.success(ButtonEvent(
    client_x:,
    client_y:,
    offset_x:,
    offset_y:,
    pointer_type:,
    button:,
  ))
}

pub type MotionEvent {
  MotionEvent(
    client_x: Float,
    client_y: Float,
    offset_x: Float,
    offset_y: Float,
    pointer_type: PointerType,
  )
}

fn motion_event_decoder() -> Decoder(MotionEvent) {
  use client_x <- decode.field("clientX", decode.float)
  use client_y <- decode.field("clientY", decode.float)
  use offset_x <- decode.field("offsetX", decode.float)
  use offset_y <- decode.field("offsetY", decode.float)
  use pointer_type <- decode.field("pointerType", pointer_type_decoder())
  decode.success(MotionEvent(
    client_x:,
    client_y:,
    offset_x:,
    offset_y:,
    pointer_type:,
  ))
}

pub type PointerType {
  Mouse
  Pen
  Touch
}

fn pointer_type_decoder() -> Decoder(PointerType) {
  use variant <- decode.then(decode.string)
  case variant {
    "mouse" -> decode.success(Mouse)
    "pen" -> decode.success(Pen)
    "touch" -> decode.success(Touch)
    _ -> decode.failure(Mouse, "PointerType")
  }
}

pub type Button {
  // left click or basic touch
  Primary
  Auxiliary
  Secondary
}

fn button_decoder() -> Decoder(Button) {
  use variant <- decode.then(decode.int)
  case variant {
    0 -> decode.success(Primary)
    1 -> decode.success(Auxiliary)
    2 -> decode.success(Secondary)
    _ -> decode.failure(Primary, "Button")
  }
}

pub fn listen_button(
  type_ type_: ButtonEventType,
  button button: Button,
  to_msg to_msg: fn(ButtonEvent) -> msg,
) -> Effect(msg) {
  use dispatch <- effect.from

  use event <- do_listen(button_event_type_to_string(type_))
  case decode.run(event, button_event_decoder()) {
    Ok(event) if event.button == button -> event |> to_msg |> dispatch
    _ -> Nil
  }
}

pub fn listen_motion(
  type_: MotionEventType,
  to_msg: fn(MotionEvent) -> msg,
) -> Effect(msg) {
  use dispatch <- effect.from

  use event <- do_listen(motion_event_type_to_string(type_))
  case decode.run(event, motion_event_decoder()) {
    Ok(event) -> event |> to_msg |> dispatch
    _ -> Nil
  }
}

@external(javascript, "./event_ffi.mjs", "listen")
fn do_listen(type_: String, listener: fn(Dynamic) -> Nil) -> Nil
