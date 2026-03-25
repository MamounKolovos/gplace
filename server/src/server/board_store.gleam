import atomic_array.{type AtomicArray}
import gleam/bool
import gleam/int

pub const bits_per_color = 4

/// bits per color divided by the maximum number of bits that can be stored in an atomic array integer
pub const colors_per_chunk = 16

const max_uint32 = 0xFFFF_FFFF

///TODO: rename to BoardStore
pub opaque type BoardStore {
  BoardStore(storage: AtomicArray, width: Int, height: Int)
}

pub fn hydrate(
  using colors: List(Int),
  width width: Int,
  height height: Int,
) -> BoardStore {
  let size = { width * height } / colors_per_chunk
  let storage = atomic_array.new_unsigned(size)

  let _ =
    int.range(0, size, with: colors, run: fn(acc, i) {
      let assert [
        c1,
        c2,
        c3,
        c4,
        c5,
        c6,
        c7,
        c8,
        c9,
        c10,
        c11,
        c12,
        c13,
        c14,
        c15,
        c16,
        ..rest
      ] = acc
      let assert <<chunk:64>> = <<
        c1:4,
        c2:4,
        c3:4,
        c4:4,
        c5:4,
        c6:4,
        c7:4,
        c8:4,
        c9:4,
        c10:4,
        c11:4,
        c12:4,
        c13:4,
        c14:4,
        c15:4,
        c16:4,
      >>

      let assert Ok(_) = atomic_array.set(storage, i, chunk)
      rest
    })

  BoardStore(storage:, width:, height:)
}

pub fn set_tile(
  board: BoardStore,
  x x: Int,
  y y: Int,
  color color: Int,
) -> Result(Nil, Nil) {
  use <- bool.guard(
    x < 0 || x >= board.width || y < 0 || y >= board.height,
    return: Error(Nil),
  )

  let tile_index = y * board.width + x
  let array_index = tile_index / 16
  let bit_offset = { tile_index % 16 } * 4

  let assert Ok(chunk) = atomic_array.get(board.storage, array_index)
  let assert <<left:size(bit_offset), _:4, right:bits>> = <<
    chunk:64,
  >>
  let assert <<chunk:64>> = <<
    left:size(bit_offset),
    color:4,
    right:bits,
  >>
  let assert Ok(_) =
    atomic_array.exchange(board.storage, at: array_index, replace_with: chunk)

  Ok(Nil)
}

pub fn to_bit_array(board: BoardStore) -> BitArray {
  do_to_bit_array(board.storage)
}

@external(erlang, "board_ffi", "to_bit_array")
fn do_to_bit_array(storage: AtomicArray) -> BitArray
