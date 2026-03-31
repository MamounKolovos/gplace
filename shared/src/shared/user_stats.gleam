import gleam/dynamic/decode.{type Decoder}
import gleam/float
import gleam/json.{type Json}
import gleam/option.{type Option}
import gleam/time/timestamp.{type Timestamp}

pub type UserStats {
  UserStats(tiles_placed: Int, last_placed_at: Option(Timestamp))
}

pub fn encode(stats: UserStats) -> String {
  to_json(stats) |> json.to_string
}

fn to_json(stats: UserStats) -> Json {
  let UserStats(tiles_placed:, last_placed_at:) = stats
  json.object([
    #("tiles_placed", json.int(tiles_placed)),
    #("last_placed_at", json.nullable(last_placed_at, of: timestamp_to_json)),
  ])
}

fn timestamp_to_json(timestamp: Timestamp) -> Json {
  timestamp.to_unix_seconds(timestamp) |> json.float
}

pub fn decoder() -> Decoder(UserStats) {
  use tiles_placed <- decode.field("tiles_placed", decode.int)
  use last_placed_at <- decode.field(
    "last_placed_at",
    decode.optional(timestamp_decoder()),
  )
  decode.success(UserStats(tiles_placed:, last_placed_at:))
}

fn timestamp_decoder() -> Decoder(Timestamp) {
  use seconds <- decode.then(decode.float)
  float.round(seconds) |> timestamp.from_unix_seconds |> decode.success
}
