import client/network
import gleam/bit_array
import gleam/dynamic/decode
import gleam/option.{type Option, None, Some}
import lustre/effect.{type Effect}
import rsvp

pub type Board {
  Board(color_indexes: BitArray, width: Int, height: Int)
}

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
  do_draw_board(ctx, board.color_indexes, board.width, board.height)
}

pub fn draw_board(
  board: Board,
  ctx: Option(Context),
  to_msg: fn(Canvas, Context) -> msg,
) -> Effect(msg) {
  use dispatch, _ <- effect.after_paint()

  let ctx = case ctx {
    Some(ctx) -> ctx
    None -> {
      let #(canvas, ctx) = do_load_canvas_and_context("base-canvas")
      to_msg(canvas, ctx) |> dispatch
      ctx
    }
  }

  do_draw_board(ctx, board.color_indexes, board.width, board.height)
}

/// passing in primitives instead of the board type directly is easier
/// since i dont have to deal with the custom type in js
@external(javascript, "./board_ffi.mjs", "drawBoard")
fn do_draw_board(
  ctx: Context,
  color_indexes: BitArray,
  width: Int,
  height: Int,
) -> Nil

@external(javascript, "./board_ffi.mjs", "setDimensions")
fn do_set_dimensions(canvas: Canvas, width: Int, height: Int) -> Nil

/// FFI reference to `HTMLCanvasElement`
pub type Canvas

/// FFI reference to `CanvasRenderingContext2D`
pub type Context

@external(javascript, "./board_ffi.mjs", "getCanvasAndContext")
fn do_load_canvas_and_context(canvas_id: String) -> #(Canvas, Context)

pub type Snapshot {
  Snapshot(color_indexes: BitArray, width: Int, height: Int)
}

pub fn fetch_snapshot(
  to_msg: fn(Result(Snapshot, network.Error)) -> msg,
) -> Effect(msg) {
  let handler = network.expect_json(snapshot_decoder(), to_msg)
  rsvp.get("/api/board", handler)
}

fn snapshot_decoder() -> decode.Decoder(Snapshot) {
  use color_indexes <- decode.field("color_indexes", decode.string)

  case bit_array.base64_decode(color_indexes) {
    Ok(color_indexes) -> {
      use width <- decode.field("width", decode.int)
      use height <- decode.field("height", decode.int)
      decode.success(Snapshot(color_indexes:, width:, height:))
    }
    Error(Nil) ->
      decode.failure(Snapshot(<<>>, -1, -1), expected: "color_indexes")
  }
}
