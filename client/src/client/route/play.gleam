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
  Loaded(board: Board, pan_state: PanState, camera_position: Vec2)
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
      ]
      #(
        session,
        Model(..model, canvas_state: Cached(canvas:, ctx:)),
        navigation_effects |> effect.batch |> effect.map(Pan),
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
      let camera_position = vec2.add(camera_origin, delta)
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
    Loaded(camera_position:, pan_state:, ..) ->
      html.div(
        [
          attribute.class("w-screen h-screen overflow-hidden"),
        ],
        [
          case model.presence_state {
            Known(user_count:) ->
              html.text("live user count: " <> int.to_string(user_count))
            Unknown -> element.none()
          },
          html.div(
            [
              translate(camera_position),
              case pan_state {
                Idle -> attribute.none()
                PanPrimed -> attribute.class("cursor-grab")
                Panning(..) -> attribute.class("cursor-grabbing")
              },
            ],
            [
              html.div(
                [
                  attribute.style("image-rendering", "pixelated"),
                  attribute.style("transform", "scale(20,20)"),
                ],
                [
                  html.canvas([
                    attribute.id("base-canvas"),
                  ]),
                ],
              ),
            ],
          ),
        ],
      )
    Failed(error_text:) -> html.text(error_text)
  }
}

fn translate(position: Vec2) -> attribute.Attribute(Msg) {
  let value =
    "translate("
    <> float.to_string(position.x)
    <> "px,"
    <> float.to_string(position.y)
    <> "px)"
  attribute.style("transform", value)
}
