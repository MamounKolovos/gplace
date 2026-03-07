import gleam/bit_array
import gleam/dynamic/decode.{type Decoder}
import gleam/json.{type Json}

pub type Snapshot {
  Snapshot(colors: BitArray, width: Int, height: Int)
}

pub fn encode(snapshot: Snapshot) -> String {
  snapshot |> to_json |> json.to_string
}

fn to_json(snapshot: Snapshot) -> Json {
  let Snapshot(colors:, width:, height:) = snapshot
  json.object([
    #("colors", colors |> bit_array.base64_encode(True) |> json.string),
    #("width", json.int(width)),
    #("height", json.int(height)),
  ])
}

pub fn decoder() -> Decoder(Snapshot) {
  use colors <- decode.field("colors", decode.string)

  case bit_array.base64_decode(colors) {
    Ok(colors) -> {
      use width <- decode.field("width", decode.int)
      use height <- decode.field("height", decode.int)
      decode.success(Snapshot(colors:, width:, height:))
    }
    Error(Nil) -> decode.failure(Snapshot(<<>>, -1, -1), expected: "colors")
  }
}
