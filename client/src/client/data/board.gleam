import client/data/vec2.{type Vec2, Vec2}
import gleam/float
import gleam/int
import gleam/list
import gleam/option.{type Option, Some}
import lustre/effect.{type Effect}

pub opaque type Board {
  Board(colors: BitArray, width: Int, height: Int)
}

pub fn new(colors: BitArray, width: Int, height: Int) -> Board {
  Board(colors:, width:, height:)
}

pub opaque type Tile {
  Tile(position: Position, color: Int)
}

pub fn new_tile(board: Board, x: Int, y: Int, color: Int) -> Result(Tile, Nil) {
  case x >= 0 && x < board.width && y >= 0 && y < board.height {
    True -> {
      let position = Position(x:, y:)
      Ok(Tile(position:, color:))
    }
    False -> Error(Nil)
  }
}

pub opaque type Position {
  Position(x: Int, y: Int)
}

pub fn new_position(board: Board, position: Vec2) -> Result(Position, Nil) {
  // flooring is necessary to avoid something like -0.3 being truncated to 0
  let x = float.floor(position.x) |> float.truncate
  let y = float.floor(position.y) |> float.truncate

  case x >= 0 && x < board.width && y >= 0 && y < board.height {
    True -> Ok(Position(x:, y:))
    False -> Error(Nil)
  }
}

pub fn snap_position(board: Board, position: Vec2) -> Position {
  // flooring is necessary to avoid something like -0.3 being truncated to 0
  let x =
    float.floor(position.x)
    |> float.truncate
    |> int.clamp(min: 0, max: board.width - 1)
  let y =
    float.floor(position.y)
    |> float.truncate
    |> int.clamp(min: 0, max: board.height - 1)

  Position(x:, y:)
}

pub fn position_to_tuple(position: Position) -> #(Int, Int) {
  #(position.x, position.y)
}

pub fn position_to_vec(position: Position) -> Vec2 {
  Vec2(x: int.to_float(position.x), y: int.to_float(position.y))
}

pub fn update(board: Board, x: Int, y: Int, color: Int) -> Board {
  let colors = do_update(board.colors, board.width, board.height, x, y, color)
  Board(..board, colors:)
}

pub fn batch_updates(board: Board, tiles: List(Tile)) -> Board {
  let colors =
    do_batch_updates(
      board.colors,
      board.width,
      board.height,
      list.map(tiles, fn(tile) {
        #(tile.position.x, tile.position.y, tile.color)
      }),
    )
  Board(..board, colors:)
}

@external(javascript, "./board_ffi.mjs", "batchUpdates")
fn do_batch_updates(
  colors: BitArray,
  width: Int,
  height: Int,
  tiles: List(#(Int, Int, Int)),
) -> BitArray

@external(javascript, "./board_ffi.mjs", "update")
fn do_update(
  colors: BitArray,
  width: Int,
  height: Int,
  x: Int,
  y: Int,
  color: Int,
) -> BitArray

pub fn init(
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
  do_draw(ctx, board.colors, board.width, board.height)
}

pub fn draw(board: Board, ctx: Context) -> Effect(msg) {
  use _ <- effect.from()

  do_draw(ctx, board.colors, board.width, board.height)
}

/// passing in primitives instead of the board type directly is easier
/// since i dont have to deal with the custom type in js
@external(javascript, "./board_ffi.mjs", "draw")
fn do_draw(ctx: Context, colors: BitArray, width: Int, height: Int) -> Nil

@external(javascript, "./board_ffi.mjs", "setDimensions")
fn do_set_dimensions(canvas: Canvas, width: Int, height: Int) -> Nil

/// FFI reference to `HTMLCanvasElement`
pub type Canvas

/// FFI reference to `CanvasRenderingContext2D`
pub type Context

@external(javascript, "./board_ffi.mjs", "getCanvasAndContext")
fn do_load_canvas_and_context(canvas_id: String) -> #(Canvas, Context)
