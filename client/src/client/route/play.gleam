import client/data/board.{type Board}
import client/data/camera.{type Camera}
import client/data/keyboard
import client/data/pointer
import client/data/vec2.{type Vec2, Vec2}
import client/data/websocket.{type WebSocket}
import client/network
import client/session.{type Session}
import gleam/float
import gleam/int
import gleam/json
import gleam/option.{type Option, None, Some}
import lustre/attribute
import lustre/effect.{type Effect}
import lustre/element.{type Element}
import lustre/element/html
import rsvp
import shared/snapshot.{type Snapshot}
import shared/transport.{type ServerMessage}

pub type Model {
  Model(board_state: BoardState, socket_state: SocketState)
}

pub type BoardState {
  Loading
  Loaded(
    board: Board,
    camera: Camera,
    canvas_handle: CanvasHandle,
    pan_state: PanState,
    tile_placement: TilePlacementState,
    pointer_position: Vec2,
  )
  Failed(error_text: String)
}

pub type TilePlacementState {
  TilePlacementIdle
  Pressed(tile: board.Tile)
}

pub type CanvasHandle {
  Unavailable
  Cached(canvas: board.Canvas, ctx: board.Context)
}

pub type SocketState {
  Connecting
  Connected(socket: WebSocket, user_count: Option(Int))
  //TODO: failed
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
  ApiReturnedSnapshot(Result(Snapshot, network.Error))
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
      fetch_snapshot(),
      websocket.init("ws://localhost:8000/api/ws", WebSocketEvent),
    ])

  #(Model(board_state: Loading, socket_state: Connecting), effect)
}

pub fn update(
  session: Session,
  model: Model,
  msg: Msg,
) -> #(Session, Model, Effect(Msg)) {
  case model, msg {
    Model(board_state: Loading, ..), ApiReturnedSnapshot(result) ->
      case result {
        Ok(snapshot) -> {
          let board = board.from_snapshot(snapshot)
          let board_state =
            Loaded(
              board:,
              camera: camera.new(),
              canvas_handle: Unavailable,
              pan_state: Idle,
              tile_placement: TilePlacementIdle,
              pointer_position: Vec2(0.0, 0.0),
            )
          let model = Model(..model, board_state:)
          #(
            session,
            model,
            board.init_board(board, None, None, DomReturnedCanvas),
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
    Model(
      board_state: Loaded(canvas_handle: Unavailable, ..) as board_state,
      ..,
    ),
      DomReturnedCanvas(canvas:, ctx:)
    -> {
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

      let board_state =
        Loaded(..board_state, canvas_handle: Cached(canvas:, ctx:))
      let model = Model(..model, board_state:)
      #(session, model, navigation_effects |> effect.batch)
    }
    Model(socket_state: Connecting, ..),
      WebSocketEvent(websocket.Opened(socket))
    -> {
      #(
        session,
        Model(..model, socket_state: Connected(socket:, user_count: None)),
        effect.none(),
      )
    }

    Model(
      board_state: Loaded(
        tile_placement: TilePlacementIdle,
        pan_state: Idle,
        board:,
        camera:,
        ..,
      ) as board_state,
      ..,
    ),
      PrimaryPointerPressedDown(event)
    -> {
      let tile =
        Vec2(event.client_x, event.client_y) |> screen_to_tile(board, camera)
      case tile {
        Ok(tile) -> {
          let tile_placement = Pressed(tile:)
          let board_state = Loaded(..board_state, tile_placement:)
          let model = Model(..model, board_state:)
          #(session, model, effect.none())
        }
        _ -> #(session, model, effect.none())
      }
    }

    Model(
      board_state: Loaded(
        pan_state: Idle,
        tile_placement: Pressed(tile: pressed_tile),
        board:,
        camera:,
        ..,
      ) as board_state,
      socket_state: Connected(socket:, ..),
    ),
      PrimaryPointerReleased(event)
    -> {
      let released_tile =
        Vec2(event.client_x, event.client_y) |> screen_to_tile(board, camera)

      let effect = case released_tile {
        Ok(released_tile) if pressed_tile == released_tile -> {
          let message =
            transport.TileChanged(
              x: released_tile.x,
              y: released_tile.y,
              color: 5,
            )
          send_client_message(socket, message)
        }
        _ -> effect.none()
      }

      let board_state = Loaded(..board_state, tile_placement: TilePlacementIdle)
      let model = Model(..model, board_state:)
      #(session, model, effect)
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

    model, WebSocketEvent(websocket.ReceivedMessage(message)) -> {
      case json.parse(message, transport.server_message_decoder()) {
        Ok(message) -> {
          let #(model, effect) = handle_server_message(model, message)
          #(session, model, effect)
        }
        // not sure what else to do other than ignore
        Error(_) -> #(session, model, effect.none())
      }
    }
    _, _ -> #(session, model, effect.none())
  }
}

fn fetch_snapshot() -> Effect(Msg) {
  let handler = network.expect_json(snapshot.decoder(), ApiReturnedSnapshot)
  rsvp.get("/api/board", handler)
}

fn screen_to_tile(
  position: Vec2,
  board: Board,
  camera: Camera,
) -> Result(board.Tile, Nil) {
  let world_position = camera.from_screen(camera, position)

  let x = float.truncate(world_position.x)
  let y = float.truncate(world_position.y)

  board.new_tile(board, x, y)
}

fn handle_server_message(
  model: Model,
  message: ServerMessage,
) -> #(Model, Effect(Msg)) {
  case model, message {
    Model(socket_state: Connected(..) as socket_state, ..),
      transport.UserCountUpdated(count:)
    -> {
      let socket_state = Connected(..socket_state, user_count: Some(count))
      let model = Model(..model, socket_state:)
      #(model, effect.none())
    }
    Model(
      board_state: Loaded(board:, canvas_handle: Cached(ctx:, ..), ..) as board_state,
      ..,
    ),
      transport.TileUpdate(x:, y:, color:)
    -> {
      let board = board.update_board(board, x, y, color)
      let board_state = Loaded(..board_state, board:)
      let model = Model(..model, board_state:)
      let effect = board.draw_board(board, ctx)
      #(model, effect)
    }
    _, _ -> #(model, effect.none())
  }
}

fn send_client_message(
  socket: WebSocket,
  message: transport.ClientMessage,
) -> Effect(Msg) {
  message
  |> transport.client_message_to_json
  |> json.to_string
  |> websocket.send(socket, _)
}

pub fn view(model: Model) -> Element(Msg) {
  case model.board_state {
    Loading -> html.text("waiting...")
    Loaded(board:, camera:, pointer_position:, pan_state:, ..) ->
      html.div([], [
        hud_view(board, camera, pointer_position, model.socket_state),
        canvas_view(camera, pan_state),
      ])
    Failed(error_text:) -> html.text(error_text)
  }
}

fn hud_view(
  board: Board,
  camera: Camera,
  pointer_position: Vec2,
  socket_state: SocketState,
) -> Element(Msg) {
  html.div([], [
    pointer_world_view(board, camera, pointer_position),
    case socket_state {
      Connected(user_count: Some(user_count), ..) -> user_count_view(user_count)
      _ -> element.none()
    },
  ])
}

fn pointer_world_view(
  board: Board,
  camera: Camera,
  pointer_position: Vec2,
) -> Element(Msg) {
  let tile = screen_to_tile(pointer_position, board, camera)

  let #(x, y) = case tile {
    Ok(tile) -> #(int.to_string(tile.x), int.to_string(tile.y))
    Error(Nil) -> #("-", "-")
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
      html.text("(" <> x <> ", " <> y <> ")"),
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
