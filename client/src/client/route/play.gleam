import client/data/board.{type Board, Board}
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
    pan_state: PanState,
    camera_position: Vec2,
    /// store in log space since wheel deltas are additive and need to be applied multiplicatively
    /// gives us smooth exponential scaling
    camera_log_zoom: Float,
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
  Panning(pan_origin: Vec2, camera_origin: Vec2)
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
  Pan(PanMsg)
  WheelChanged(pointer.WheelEvent)
  PointerMoved1(pointer.MotionEvent)
}

pub type PanMsg {
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
                pan_state: Idle,
                camera_position: Vec2(0.0, 0.0),
                camera_log_zoom: 0.0,
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
        keyboard.lifecycle(keyboard.Space, SpaceChanged) |> effect.map(Pan),
        pointer.listen_motion(pointer.PointerMove, PointerMoved)
          |> effect.map(Pan),
        pointer.listen_button(
          pointer.PointerDown,
          button: pointer.Primary,
          to_msg: PrimaryPointerPressedDown,
        )
          |> effect.map(Pan),
        pointer.listen_button(
          pointer.PointerUp,
          button: pointer.Primary,
          to_msg: PrimaryPointerReleased,
        )
          |> effect.map(Pan),
        pointer.listen_wheel(WheelChanged),
        pointer.listen_motion(pointer.PointerMove, PointerMoved1),
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

    Model(board_state:, ..), Pan(msg) -> {
      let board_state = update_board_pan(board_state, msg)
      #(session, Model(..model, board_state:), effect.none())
    }

    Model(board_state: Loaded(..) as board_state, ..), PointerMoved1(event) -> {
      let pointer_position = Vec2(event.client_x, event.client_y)
      #(
        session,
        Model(..model, board_state: Loaded(..board_state, pointer_position:)),
        effect.none(),
      )
    }

    Model(
      board_state: Loaded(
        camera_log_zoom:,
        camera_position:,
        pointer_position:,
        ..,
      ) as board_state,
      ..,
    ),
      WheelChanged(event)
    -> {
      let new_camera_log_zoom =
        float.clamp(
          camera_log_zoom +. { event.delta_y *. 0.003 },
          // ln(1)
          min: 0.0,
          // ln(100)
          max: 4.60517,
        )

      // transform back from log space since the ratio is calculated in normal space
      let old_zoom = float.exponential(camera_log_zoom)
      let new_zoom = float.exponential(new_camera_log_zoom)

      let zoom_ratio = new_zoom /. old_zoom

      // anchor point by default is (0, 0)
      // this is the formula to make the pointer the anchor point instead
      // camera * r pulls the camera towards (0, 0)
      // pointer * (r - 1) pushes the camera towards the pointer
      let new_camera_position =
        vec2.add(
          vec2.mul(camera_position, zoom_ratio),
          vec2.mul(pointer_position, zoom_ratio -. 1.0),
        )

      #(
        session,
        Model(
          ..model,
          board_state: Loaded(
            ..board_state,
            camera_log_zoom: new_camera_log_zoom,
            camera_position: new_camera_position,
          ),
        ),
        effect.none(),
      )
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

fn update_board_pan(state: BoardState, msg: PanMsg) -> BoardState {
  case state, msg {
    Loaded(..), SpaceChanged(is_down:) ->
      Loaded(..state, pan_state: case is_down {
        True -> PanPrimed
        False -> Idle
      })
    Loaded(pan_state: PanPrimed, camera_position:, ..),
      PrimaryPointerPressedDown(event)
    ->
      Loaded(
        ..state,
        pan_state: Panning(
          pan_origin: Vec2(event.client_x, event.client_y),
          camera_origin: camera_position,
        ),
      )
    Loaded(pan_state: Panning(pan_origin:, camera_origin:), ..),
      PointerMoved(event)
    -> {
      let current_position = Vec2(event.client_x, event.client_y)
      let delta = vec2.sub(current_position, pan_origin)
      let camera_position = vec2.sub(camera_origin, delta)
      Loaded(..state, camera_position:)
    }
    Loaded(pan_state: Panning(..), ..), PrimaryPointerReleased(_) ->
      Loaded(..state, pan_state: PanPrimed)
    state, _ -> state
  }
}

pub fn view(model: Model) -> Element(Msg) {
  case model.board_state {
    Loading -> html.text("waiting...")
    Loaded(camera_position:, camera_log_zoom:, pan_state:, ..) ->
      canvas_view(camera_position, camera_log_zoom, pan_state)
    Failed(error_text:) -> html.text(error_text)
  }
}

fn canvas_view(
  camera_position: Vec2,
  camera_log_zoom: Float,
  pan_state: PanState,
) -> Element(Msg) {
  html.div(
    [
      attribute.class("w-screen h-screen overflow-hidden"),
    ],
    [
      // case model.presence_state {
      //   Known(user_count:) ->
      //     html.text("live user count: " <> int.to_string(user_count))
      //   Unknown -> element.none()
      // },
      html.div(
        [
          attribute.style("image-rendering", "pixelated"),
          attribute.style("transform-origin", "0 0"),
          attribute.style(
            "transform",
            css_translate(vec2.neg(camera_position))
              <> css_scale(float.exponential(camera_log_zoom)),
          ),
          case pan_state {
            Idle -> attribute.none()
            PanPrimed -> attribute.class("cursor-grab")
            Panning(..) -> attribute.class("cursor-grabbing")
          },
        ],
        [
          html.canvas([
            attribute.id("base-canvas"),
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
