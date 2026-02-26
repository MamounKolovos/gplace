import client/data/board.{type Board, Board}
import client/data/websocket.{type WebSocket}
import client/network
import client/session.{type Session}
import gleam/int
import gleam/option.{type Option, None, Some}
import lustre/attribute
import lustre/effect.{type Effect}
import lustre/element.{type Element}
import lustre/element/html
import shared/api_error.{ApiError}

pub type Model {
  Model(
    board_state: BoardState,
    socket_state: SocketState,
    canvas_state: CanvasState,
    presence_state: PresenceState,
  )
}

pub type BoardState {
  Loading
  Loaded(board: Board)
  Failed(error_text: String)
}

pub type SocketState {
  Connecting
  Connected(socket: WebSocket)
  //TODO: failed
}

pub type CanvasState {
  Unmounted
  Mounted(ctx: board.Context)
}

pub type PresenceState {
  Unknown
  Known(user_count: Int)
}

pub type Msg {
  DomReturnedCanvas(canvas: board.Canvas, ctx: board.Context)
  ApiReturnedSnapshot(Result(board.Snapshot, network.Error))
  WebSocketEvent(websocket.Event)
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
      canvas_state: Unmounted,
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
  echo msg
  case model, msg {
    Model(board_state: Loading, ..), ApiReturnedSnapshot(result) ->
      case result {
        Ok(board.Snapshot(color_indexes:, width:, height:)) -> {
          let board = Board(color_indexes:, width:, height:)
          #(
            session,
            Model(..model, board_state: Loaded(board:)),
            board.draw_board(board, None, DomReturnedCanvas),
          )
        }
        Error(error) -> #(
          session,
          Model(
            ..model,
            board_state: Failed(error_text: "board could not be loaded :("),
          ),
          effect.none(),
        )
      }
    Model(canvas_state: Unmounted, ..), DomReturnedCanvas(canvas: _, ctx:) -> {
      #(session, Model(..model, canvas_state: Mounted(ctx:)), effect.none())
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
    Loaded(board:) ->
      html.div([], [
        html.text(case model.presence_state {
          Known(user_count:) -> "live user count: " <> int.to_string(user_count)
          Unknown -> "..."
        }),
        html.div([attribute.style("image-rendering", "pixelated")], [
          html.canvas([
            attribute.id("base-canvas"),
            attribute.width(board.width),
            attribute.height(board.height),
          ]),
        ]),
      ])
    Failed(error_text:) -> html.text(error_text)
  }
}
