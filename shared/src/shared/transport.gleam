import gleam/dynamic/decode.{type Decoder}
import gleam/json.{type Json}

pub type ClientMessage {
  TileChanged(x: Int, y: Int, color: Int)
}

pub fn client_message_decoder() -> Decoder(ClientMessage) {
  use x <- decode.field("x", decode.int)
  use y <- decode.field("y", decode.int)
  use color <- decode.field("color", decode.int)
  decode.success(TileChanged(x:, y:, color:))
}

pub fn client_message_to_json(client_message: ClientMessage) -> Json {
  let TileChanged(x:, y:, color:) = client_message
  json.object([
    #("x", json.int(x)),
    #("y", json.int(y)),
    #("color", json.int(color)),
  ])
}

pub type ServerMessage {
  UserCountUpdated(count: Int)
  TileUpdate(x: Int, y: Int, color: Int)
}

pub fn server_message_decoder() -> Decoder(ServerMessage) {
  use variant <- decode.field("type", decode.string)
  case variant {
    "USER_COUNT_UPDATE" -> {
      use count <- decode.field("count", decode.int)
      decode.success(UserCountUpdated(count:))
    }
    "TILE_UPDATE" -> {
      use x <- decode.field("x", decode.int)
      use y <- decode.field("y", decode.int)
      use color <- decode.field("color", decode.int)
      decode.success(TileUpdate(x:, y:, color:))
    }
    _ -> decode.failure(UserCountUpdated(count: -1), "ServerMessage")
  }
}

pub fn server_message_to_json(server_message: ServerMessage) -> Json {
  case server_message {
    UserCountUpdated(count:) ->
      json.object([
        #("type", json.string("USER_COUNT_UPDATE")),
        #("count", json.int(count)),
      ])
    TileUpdate(x:, y:, color:) ->
      json.object([
        #("type", json.string("TILE_UPDATE")),
        #("x", json.int(x)),
        #("y", json.int(y)),
        #("color", json.int(color)),
      ])
  }
}
