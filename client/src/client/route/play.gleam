import client/data/board.{type Board}
import client/data/camera.{type Camera}
import client/data/engine
import client/data/keyboard
import client/data/pointer
import client/data/vec2.{type Vec2, Vec2}
import client/data/websocket.{type WebSocket}
import client/network
import client/session.{type Session}
import gleam/bool
import gleam/float
import gleam/int
import gleam/json
import gleam/list
import gleam/option.{type Option, None, Some}
import lustre/attribute
import lustre/effect.{type Effect}
import lustre/element.{type Element}
import lustre/element/html
import rsvp
import shared/snapshot.{type Snapshot, Snapshot}
import shared/transport.{type ServerMessage}

pub type Model {
  Model(state: State)
}

pub type State {
  SocketFailedToConnect
  BoardFailedToLoad(error_text: String)

  SocketConnecting
  Initializing(
    socket: WebSocket,
    user_count: Option(Int),
    updates: List(TileUpdate),
  )
  BoardLoaded(
    board: Board,
    camera: Camera,
    canvas_handle: CanvasHandle,
    pan_state: PanState,
    tile_placement: TilePlacementState,
    pointer_position: Vec2,
    socket: WebSocket,
    user_count: Option(Int),
  )
}

pub type TileUpdate {
  TileUpdate(x: Int, y: Int, color: Int)
}

pub type TilePlacementState {
  TilePlacementIdle
  Pressed(position: board.Position)
}

//TODO: add this to initializaing maybe?
pub type CanvasHandle {
  Unavailable
  Cached(canvas: board.Canvas, ctx: board.Context)
}

pub type PanState {
  Idle
  PanPrimed
  Panning(last_pointer_position: Vec2)
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
  FrameTicked(dt: Float)
}

pub fn init() -> #(Model, Effect(Msg)) {
  let effect = websocket.init("ws://localhost:8000/api/ws", WebSocketEvent)

  #(Model(state: SocketConnecting), effect)
}

pub fn update(
  session: Session,
  model: Model,
  msg: Msg,
) -> #(Session, Model, Effect(Msg)) {
  case model, msg {
    Model(state: Initializing(socket:, user_count:, updates:)),
      ApiReturnedSnapshot(result)
    ->
      case result {
        Ok(Snapshot(colors:, width:, height:)) -> {
          let board = board.new(colors, width, height)

          let tiles =
            list.filter_map(updates, fn(update) {
              let TileUpdate(x:, y:, color:) = update
              board.new_tile(board, x, y, color)
            })

          let board = board.batch_updates(board, tiles)

          let state =
            BoardLoaded(
              board:,
              camera: camera.new(),
              canvas_handle: Unavailable,
              pan_state: Idle,
              tile_placement: TilePlacementIdle,
              pointer_position: Vec2(0.0, 0.0),
              socket:,
              user_count:,
            )
          let model = Model(state:)
          let effect =
            effect.batch([
              board.init(board, None, None, DomReturnedCanvas),
              engine.start(FrameTicked),
            ])
          #(session, model, effect)
        }
        Error(_) -> #(
          session,
          Model(state: BoardFailedToLoad(
            error_text: "board could not be loaded :(",
          )),
          effect.none(),
        )
      }
    Model(state: BoardLoaded(canvas_handle: Unavailable, ..) as state),
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

      let state = BoardLoaded(..state, canvas_handle: Cached(canvas:, ctx:))
      let model = Model(state:)
      #(session, model, effect.batch(navigation_effects))
    }
    Model(state: SocketConnecting), WebSocketEvent(websocket.Opened(socket)) -> {
      #(
        session,
        Model(state: Initializing(socket:, user_count: None, updates: [])),
        fetch_snapshot(),
      )
    }

    Model(
      state: BoardLoaded(
        tile_placement: TilePlacementIdle,
        pan_state: Idle,
        board:,
        camera:,
        ..,
      ) as state,
    ),
      PrimaryPointerPressedDown(event)
    -> {
      let position =
        Vec2(event.client_x, event.client_y)
        |> screen_to_board_space(board, camera)
      case position {
        Ok(position) -> {
          let tile_placement = Pressed(position:)
          let state = BoardLoaded(..state, tile_placement:)
          let model = Model(state:)
          #(session, model, effect.none())
        }
        _ -> #(session, model, effect.none())
      }
    }

    Model(
      state: BoardLoaded(board:, camera:, canvas_handle: Cached(ctx:, ..), ..) as state,
    ),
      FrameTicked(dt:)
    -> {
      let camera = camera.update(camera, dt)
      let state = BoardLoaded(..state, camera:)
      let model = Model(state:)
      let effect = board.draw(board, ctx)
      #(session, model, effect)
    }
    Model(
      state: BoardLoaded(
        pan_state: Idle,
        tile_placement: Pressed(position: pressed_position),
        board:,
        camera:,
        ..,
      ) as state,
    ),
      PrimaryPointerReleased(event)
    -> {
      let released_position =
        Vec2(event.client_x, event.client_y)
        |> screen_to_board_space(board, camera)

      let camera = case released_position {
        Ok(released_position) if pressed_position == released_position -> {
          let target_position = board_to_world_space(released_position)
          let target_zoom = 50.0
          camera.start_tile_focus_animation(
            camera,
            duration: 1.5,
            target_position: target_position,
            target_zoom: target_zoom,
          )
        }
        _ -> camera
      }

      let state =
        BoardLoaded(..state, camera:, tile_placement: TilePlacementIdle)
      let model = Model(state:)
      #(session, model, effect.none())
      // let released_position =
      //   Vec2(event.client_x, event.client_y)
      //   |> screen_to_board_space(board, camera)

      // let effect = case released_position {
      //   Ok(released_position) if pressed_position == released_position -> {
      //     let #(x, y) = board.position_to_tuple(released_position)
      //     let message = transport.TileChanged(x:, y:, color: 5)
      //     send_client_message(socket, message)
      //   }
      //   _ -> effect.none()
      // }

      // let state = BoardLoaded(..state, tile_placement: TilePlacementIdle)
      // let model = Model(state:)
      // #(session, model, effect)
    }

    Model(state: BoardLoaded(..) as state), SpaceChanged(is_down:) -> {
      let pan_state = case is_down {
        True -> PanPrimed
        False -> Idle
      }
      let state = BoardLoaded(..state, pan_state:)
      let model = Model(state:)
      #(session, model, effect.none())
    }

    Model(state: BoardLoaded(pan_state: PanPrimed, ..) as state),
      PrimaryPointerPressedDown(event)
    -> {
      let last_pointer_position = Vec2(event.client_x, event.client_y)
      let pan_state = Panning(last_pointer_position:)
      let state = BoardLoaded(..state, pan_state:)
      let model = Model(state:)
      #(session, model, effect.none())
    }

    Model(state: BoardLoaded(pan_state: Panning(..), ..) as state),
      PrimaryPointerReleased(_)
    -> {
      let state = BoardLoaded(..state, pan_state: PanPrimed)
      let model = Model(state:)
      #(session, model, effect.none())
    }

    Model(state: BoardLoaded(camera:, ..) as state), PointerMoved(event) -> {
      let pointer_position = Vec2(event.client_x, event.client_y)
      let state = case state.pan_state {
        Panning(last_pointer_position:) -> {
          // order reversed since camera moves opposite to pan direction
          let delta = vec2.sub(last_pointer_position, pointer_position)
          let camera = camera.pan(camera, delta)
          let pan_state = Panning(last_pointer_position: pointer_position)
          BoardLoaded(..state, pan_state:, pointer_position:, camera:)
        }
        _ -> BoardLoaded(..state, pointer_position:)
      }
      let model = Model(state:)
      #(session, model, effect.none())
    }

    Model(state: BoardLoaded(camera:, pointer_position:, ..) as state),
      WheelChanged(event)
    -> {
      use <- bool.guard(camera.is_animation_active(camera), return: #(
        session,
        model,
        effect.none(),
      ))

      let camera =
        camera.zoom_by(
          camera,
          delta: event.delta_y *. 0.003,
          target: pointer_position,
        )

      let state = BoardLoaded(..state, camera:)
      let model = Model(state:)
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

fn board_to_world_space(position: board.Position) -> camera.Position {
  board.position_to_vec(position)
  |> camera.vec_to_world
}

fn screen_to_board_space(
  position: Vec2,
  board: Board,
  camera: Camera,
) -> Result(board.Position, Nil) {
  camera.screen_to_world(camera, position)
  |> camera.world_to_vec
  |> board.new_position(board, _)
}

/// screen -> world -> board -> world -> screen
fn snap_to_board_space(position: Vec2, board: Board, camera: Camera) -> Vec2 {
  camera.screen_to_world(camera, position)
  |> camera.world_to_vec
  |> board.snap_position(board, _)
  |> board.position_to_vec
  |> camera.vec_to_world
  |> camera.world_to_screen(camera, _)
}

fn handle_server_message(
  model: Model,
  message: ServerMessage,
) -> #(Model, Effect(Msg)) {
  case model, message {
    Model(state: Initializing(..) as state), transport.UserCountUpdated(count:) -> {
      let state = Initializing(..state, user_count: Some(count))
      let model = Model(state:)
      #(model, effect.none())
    }
    Model(state: BoardLoaded(..) as state), transport.UserCountUpdated(count:) -> {
      let state = BoardLoaded(..state, user_count: Some(count))
      let model = Model(state:)
      #(model, effect.none())
    }
    Model(state: Initializing(updates:, ..) as state),
      transport.TileUpdate(x:, y:, color:)
    -> {
      let state =
        Initializing(..state, updates: [TileUpdate(x:, y:, color:), ..updates])
      let model = Model(state:)
      #(model, effect.none())
    }
    Model(state: BoardLoaded(board:, ..) as state),
      transport.TileUpdate(x:, y:, color:)
    -> {
      let board = board.update(board, x, y, color)
      let state = BoardLoaded(..state, board:)
      let model = Model(state:)
      #(model, effect.none())
    }
    _, _ -> #(model, effect.none())
  }
}

fn send_client_message(
  socket: WebSocket,
  message: transport.ClientMessage,
) -> Effect(Msg) {
  message
  |> transport.encode_client_message
  |> websocket.send(socket, _)
}

pub fn view(model: Model) -> Element(Msg) {
  case model.state {
    BoardLoaded(board:, camera:, pointer_position:, pan_state:, user_count:, ..) ->
      html.div([], [
        hud_view(board, camera, pointer_position, user_count),
        canvas_view(camera, pan_state),
      ])
    BoardFailedToLoad(error_text:) -> html.text(error_text)
    _ -> html.text("waiting...")
  }
}

fn hud_view(
  board: Board,
  camera: Camera,
  pointer_position: Vec2,
  user_count: Option(Int),
) -> Element(Msg) {
  html.div([], [
    // too zoomed out to see so no point rendering it
    case camera.zoom(camera) >. 10.0 {
      True -> tile_snapper_view(board, camera, pointer_position)
      False -> element.none()
    },
    pointer_world_view(board, camera, pointer_position),
    case user_count {
      Some(user_count) -> user_count_view(user_count)
      _ -> element.none()
    },
  ])
}

fn tile_snapper_view(
  board: Board,
  camera: Camera,
  pointer_position: Vec2,
) -> Element(Msg) {
  let position = snap_to_board_space(pointer_position, board, camera)

  html.div(
    [
      attribute.class(
        "fixed "
        <> css_size_px(camera.max_zoom, camera.max_zoom)
        <> " pointer-events-none z-50
        outline-3 outline-black",
      ),
      attribute.style("transform-origin", "0 0"),
      attribute.style(
        "transform",
        css_translate(position) <> css_scale(camera.zoom(camera) /. 100.0),
      ),
    ],
    [],
  )
}

fn css_size_px(width: Int, height: Int) -> String {
  let width = "w-[" <> int.to_string(width) <> "px]"
  let height = "h-[" <> int.to_string(height) <> "px]"
  width <> " " <> height
}

fn pointer_world_view(
  board: Board,
  camera: Camera,
  pointer_position: Vec2,
) -> Element(Msg) {
  let position = screen_to_board_space(pointer_position, board, camera)

  let #(x, y) = case position {
    Ok(position) -> {
      let #(x, y) = board.position_to_tuple(position)
      #(int.to_string(x), int.to_string(y))
    }
    Error(_) -> #("-", "-")
  }

  let zoom = { camera.zoom(camera) |> float.truncate |> int.to_string } <> "x"

  let text = "(" <> x <> ", " <> y <> ")" <> " " <> zoom

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
      html.text(text),
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
