import client/data/board.{type Board, Board}
import client/data/camera.{type Camera}
import client/data/keyboard
import client/data/pointer
import client/data/vec2.{type Vec2, Vec2}
import client/data/websocket.{type WebSocket}
import client/network
import client/session.{type Session}
import gleam/float
import gleam/int
import gleam/option.{None, Some}
import lustre/attribute
import lustre/effect.{type Effect}
import lustre/element.{type Element}
import lustre/element/html

pub type Model {
  Model(
    board_state: BoardState,
    socket_state: SocketState,
    canvas_state: CanvasHandle,
    presence_state: PresenceState,
  )
}

pub type BoardState {
  Loading
  Loaded(
    board: Board,
    camera: Camera,
    pan_state: PanState,
    pointer_position: Vec2,
  )
  Failed(error_text: String)
}

pub type SocketState {
  Connecting
  Connected(socket: WebSocket)
  //TODO: failed
}

pub type CanvasHandle {
  Unavailable
  Cached(canvas: board.Canvas, ctx: board.Context)
}

pub type PanState {
  Idle
  PanPrimed
  Panning(last_pointer_position: Vec2)
}

//TODO: have socket state own this
pub type PresenceState {
  Unknown
  Known(user_count: Int)
}

pub type Msg {
  DomReturnedCanvas(canvas: board.Canvas, ctx: board.Context)
  ApiReturnedSnapshot(Result(board.Snapshot, network.Error))
  WebSocketEvent(websocket.Event)
  WheelChanged(pointer.WheelEvent)
  SpaceChanged(is_down: Bool)
  PrimaryPointerPressedDown(pointer.ButtonEvent)
  PrimaryPointerReleased(pointer.ButtonEvent)
  PointerMoved(pointer.MotionEvent)
}

pub fn init() -> #(Model, Effect(Msg)) {
  let effect =
    effect.batch([
      board.fetch_snapshot(ApiReturnedSnapshot),
      websocket.init("ws://localhost:8000/api/ws", WebSocketEvent),
    ])

  #(
    Model(
      board_state: Loading,
      socket_state: Connecting,
      canvas_state: Unavailable,
      presence_state: Unknown,
    ),
    effect,
  )
}

pub fn update(
  session: Session,
  model: Model,
  msg: Msg,
) -> #(Session, Model, Effect(Msg)) {
  case model, msg {
    Model(board_state: Loading, canvas_state:, ..), ApiReturnedSnapshot(result) ->
      case result {
        Ok(board.Snapshot(color_indexes:, width:, height:)) -> {
          let board = Board(color_indexes:, width:, height:)
          #(
            session,
            Model(
              ..model,
              board_state: Loaded(
                board:,
                camera: camera.new(),
                pan_state: Idle,
                pointer_position: Vec2(0.0, 0.0),
              ),
            ),
            case canvas_state {
              Unavailable ->
                board.init_board(board, None, None, DomReturnedCanvas)
              Cached(canvas:, ctx:) ->
                board.init_board(
                  board,
                  Some(canvas),
                  Some(ctx),
                  DomReturnedCanvas,
                )
            },
          )
        }
        Error(_) -> #(
          session,
          Model(
            ..model,
            board_state: Failed(error_text: "board could not be loaded :("),
          ),
          effect.none(),
        )
      }
    Model(canvas_state: Unavailable, ..), DomReturnedCanvas(canvas:, ctx:) -> {
      let navigation_effects = [
        keyboard.lifecycle(keyboard.Space, SpaceChanged),
        pointer.listen_motion(pointer.PointerMove, PointerMoved),
        pointer.listen_button(
          pointer.PointerDown,
          button: pointer.Primary,
          to_msg: PrimaryPointerPressedDown,
        ),
        pointer.listen_button(
          pointer.PointerUp,
          button: pointer.Primary,
          to_msg: PrimaryPointerReleased,
        ),
        pointer.listen_wheel(WheelChanged),
      ]
      #(
        session,
        Model(..model, canvas_state: Cached(canvas:, ctx:)),
        navigation_effects |> effect.batch,
      )
    }
    Model(socket_state: Connecting, ..),
      WebSocketEvent(websocket.Opened(socket))
    -> {
      #(
        session,
        Model(..model, socket_state: Connected(socket:)),
        effect.none(),
      )
    }

    Model(board_state: Loaded(..) as board_state, ..), SpaceChanged(is_down:) -> {
      let pan_state = case is_down {
        True -> PanPrimed
        False -> Idle
      }
      let board_state = Loaded(..board_state, pan_state:)
      let model = Model(..model, board_state:)
      #(session, model, effect.none())
    }

    Model(board_state: Loaded(pan_state: PanPrimed, ..) as board_state, ..),
      PrimaryPointerPressedDown(event)
    -> {
      let last_pointer_position = Vec2(event.client_x, event.client_y)
      let pan_state = Panning(last_pointer_position:)
      let board_state = Loaded(..board_state, pan_state:)
      let model = Model(..model, board_state:)
      #(session, model, effect.none())
    }

    Model(board_state: Loaded(pan_state: Panning(..), ..) as board_state, ..),
      PrimaryPointerReleased(_)
    -> {
      let board_state = Loaded(..board_state, pan_state: PanPrimed)
      let model = Model(..model, board_state:)
      #(session, model, effect.none())
    }

    Model(board_state: Loaded(camera:, ..) as board_state, ..),
      PointerMoved(event)
    -> {
      let pointer_position = Vec2(event.client_x, event.client_y)
      let board_state = case board_state.pan_state {
        Panning(last_pointer_position:) -> {
          // order reversed since camera moves opposite to pan direction
          let delta = vec2.sub(last_pointer_position, pointer_position)
          let camera = camera.pan(camera, delta)
          let pan_state = Panning(last_pointer_position: pointer_position)
          Loaded(..board_state, pan_state:, pointer_position:, camera:)
        }
        _ -> Loaded(..board_state, pointer_position:)
      }
      let model = Model(..model, board_state:)
      #(session, model, effect.none())
    }

    Model(
      board_state: Loaded(camera:, pointer_position:, ..) as board_state,
      ..,
    ),
      WheelChanged(event)
    -> {
      let camera =
        camera.zoom_by(
          camera,
          delta: event.delta_y *. 0.003,
          target: pointer_position,
        )

      let board_state = Loaded(..board_state, camera:)
      let model = Model(..model, board_state:)
      #(session, model, effect.none())
    }

    // TODO: actually decode messages into json
    model, WebSocketEvent(websocket.ReceivedMessage(message)) -> {
      let assert Ok(user_count) = int.parse(message)
      let model = Model(..model, presence_state: Known(user_count:))
      #(session, model, effect.none())
    }
    _, _ -> #(session, model, effect.none())
  }
}

pub fn view(model: Model) -> Element(Msg) {
  case model.board_state {
    Loading -> html.text("waiting...")
    Loaded(camera:, pointer_position:, pan_state:, ..) ->
      html.div([], [
        hud_view(camera, pointer_position, model.presence_state),
        canvas_view(camera, pan_state),
      ])
    Failed(error_text:) -> html.text(error_text)
  }
}

fn hud_view(
  camera: Camera,
  pointer_position: Vec2,
  presence_state: PresenceState,
) -> Element(Msg) {
  html.div([], [
    pointer_world_view(camera, pointer_position),
    case presence_state {
      Known(user_count:) -> user_count_view(user_count)
      Unknown -> element.none()
    },
  ])
}

fn pointer_world_view(camera: Camera, pointer_position: Vec2) -> Element(Msg) {
  let pointer_world = camera.from_screen(camera, pointer_position)

  // TODO: _string suffix necessary because of compiler bug
  // fixed on main so be sure to remove once new compiler version is out
  let #(x_string, y_string) = case pointer_world {
    Vec2(x:, y:) if x >=. 0.0 && x <. 1000.0 && y >=. 0.0 && y <. 1000.0 -> #(
      x |> float.truncate |> int.to_string,
      y |> float.truncate |> int.to_string,
    )
    _ -> #("-", "-")
  }

  html.div(
    [
      attribute.class(
        "
        fixed top-4 left-1/2 -translate-x-1/2 z-50
        rounded-full
        bg-white/90 text-black
        px-3 py-1.5
        ",
      ),
    ],
    [
      html.text("(" <> x_string <> ", " <> y_string <> ")"),
    ],
  )
}

fn user_count_view(user_count: Int) -> Element(Msg) {
  html.div(
    [
      attribute.class(
        // "fixed top-4 left-1/2 -translate-x-1/2 z-50
        "fixed top-4 right-4 z-50
            rounded-full
            bg-white/90 text-black 
            px-3 py-1.5
            ",
      ),
    ],
    [html.text("live user count: " <> int.to_string(user_count))],
  )
}

fn canvas_view(camera: Camera, pan_state: PanState) -> Element(Msg) {
  html.div(
    [
      attribute.class("w-screen h-screen overflow-hidden"),
    ],
    [
      html.div(
        [
          attribute.style("image-rendering", "pixelated"),
          attribute.style("transform-origin", "0 0"),
          attribute.style(
            "transform",
            css_translate(camera.to_screen(camera) |> vec2.neg)
              <> css_scale(camera.zoom(camera)),
          ),
        ],
        [
          html.canvas([
            attribute.id("base-canvas"),
            case pan_state {
              Idle -> attribute.none()
              PanPrimed -> attribute.class("cursor-grab")
              Panning(..) -> attribute.class("cursor-grabbing")
            },
          ]),
        ],
      ),
    ],
  )
}

fn css_translate(position: Vec2) -> String {
  "translate("
  <> float.to_string(position.x)
  <> "px,"
  <> float.to_string(position.y)
  <> "px)"
}

fn css_scale(value: Float) -> String {
  "scale(" <> float.to_string(value) <> "," <> float.to_string(value) <> ")"
}
