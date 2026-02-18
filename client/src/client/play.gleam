import client/board.{type Board, Board}
import client/network
import client/session.{type Session}
import gleam/option.{type Option, None, Some}
import lustre/attribute
import lustre/effect.{type Effect}
import lustre/element.{type Element}
import lustre/element/html
import shared/api_error.{ApiError}

pub type Model {
  Model(state: State)
}

pub type State {
  WaitingForSnapshot(error_text: Option(String))
  WaitingForCanvasHandle(snapshot: board.Snapshot)
  Ready(board: Board)
}

pub type Msg {
  DomReturnedCanvas(canvas: board.Canvas, ctx: board.Context)
  ApiReturnedSnapshot(Result(board.Snapshot, network.Error))
}

pub fn init() -> #(Model, Effect(Msg)) {
  #(
    Model(state: WaitingForSnapshot(error_text: None)),
    board.fetch_snapshot(ApiReturnedSnapshot),
  )
}

pub fn update(
  session: Session,
  model: Model,
  msg: Msg,
) -> #(Session, Model, Effect(Msg)) {
  case model, msg {
    Model(state: WaitingForSnapshot(_)), ApiReturnedSnapshot(result) ->
      case result {
        Ok(snapshot) -> #(
          session,
          Model(state: WaitingForCanvasHandle(snapshot:)),
          board.load_canvas_and_context("base-canvas", DomReturnedCanvas),
        )
        Error(error) -> #(
          session,
          Model(
            state: WaitingForSnapshot(error_text: Some(
              "board could not be loaded :(",
            )),
          ),
          effect.none(),
        )
      }
    Model(state: WaitingForCanvasHandle(snapshot:)),
      DomReturnedCanvas(canvas:, ctx:)
    -> {
      let board = Board(canvas:, ctx:, snapshot:)
      #(session, Model(state: Ready(board:)), board.draw_board(board))
    }
    _, _ -> #(session, model, effect.none())
  }
}

pub fn view(model: Model) -> Element(Msg) {
  case model.state {
    WaitingForSnapshot(error_text:) ->
      case error_text {
        Some(error_text) -> html.text(error_text)
        None -> html.text("waiting...")
      }
    WaitingForCanvasHandle(snapshot:) ->
      html.div([attribute.style("image-rendering", "pixelated")], [
        html.canvas([
          attribute.id("base-canvas"),
          attribute.width(snapshot.width),
          attribute.height(snapshot.height),
        ]),
      ])
    Ready(board:) ->
      html.div([attribute.style("image-rendering", "pixelated")], [
        html.canvas([
          attribute.id("base-canvas"),
          attribute.width(board.snapshot.width),
          attribute.height(board.snapshot.height),
        ]),
      ])
  }
}
