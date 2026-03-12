import gleam/option.{type Option, Some}
import lustre/effect.{type Effect}
import shared/snapshot.{type Snapshot, Snapshot}

pub opaque type Board {
  Board(colors: BitArray, width: Int, height: Int)
}

pub fn from_snapshot(snapshot: Snapshot) -> Board {
  let Snapshot(colors:, width:, height:) = snapshot
  Board(colors:, width:, height:)
}

//TODO: make opaque
pub type Tile {
  Tile(x: Int, y: Int)
}

pub fn new_tile(board: Board, x: Int, y: Int) -> Result(Tile, Nil) {
  case x >= 0 && x < board.width && y >= 0 && y < board.height {
    True -> Ok(Tile(x:, y:))
    False -> Error(Nil)
  }
}

pub fn update_board(board: Board, x: Int, y: Int, color: Int) -> Board {
  let colors =
    do_update_board(board.colors, board.width, board.height, x, y, color)
  Board(..board, colors:)
}

@external(javascript, "./board_ffi.mjs", "updateBoard")
fn do_update_board(
  colors: BitArray,
  width: Int,
  height: Int,
  x: Int,
  y: Int,
  color: Int,
) -> BitArray

pub fn init_board(
  board: Board,
  canvas: Option(Canvas),
  ctx: Option(Context),
  to_msg: fn(Canvas, Context) -> msg,
) -> Effect(msg) {
  use dispatch, _ <- effect.after_paint

  let #(canvas, ctx) = case canvas, ctx {
    Some(canvas), Some(ctx) -> #(canvas, ctx)
    _, _ -> {
      let #(canvas, ctx) = do_load_canvas_and_context("base-canvas")
      to_msg(canvas, ctx) |> dispatch
      #(canvas, ctx)
    }
  }

  do_set_dimensions(canvas, board.width, board.height)
  do_draw_board(ctx, board.colors, board.width, board.height)
}

pub fn draw_board(board: Board, ctx: Context) -> Effect(msg) {
  use _ <- effect.from()

  do_draw_board(ctx, board.colors, board.width, board.height)
}

/// passing in primitives instead of the board type directly is easier
/// since i dont have to deal with the custom type in js
@external(javascript, "./board_ffi.mjs", "drawBoard")
fn do_draw_board(ctx: Context, colors: BitArray, width: Int, height: Int) -> Nil

@external(javascript, "./board_ffi.mjs", "setDimensions")
fn do_set_dimensions(canvas: Canvas, width: Int, height: Int) -> Nil

/// FFI reference to `HTMLCanvasElement`
pub type Canvas

/// FFI reference to `CanvasRenderingContext2D`
pub type Context

@external(javascript, "./board_ffi.mjs", "getCanvasAndContext")
fn do_load_canvas_and_context(canvas_id: String) -> #(Canvas, Context)
