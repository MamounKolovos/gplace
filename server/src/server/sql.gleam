//// This module contains the code to run the sql queries defined in
//// `./src/server/sql`.
//// > 🐿️ This module was generated automatically using v4.6.0 of
//// > the [squirrel package](https://github.com/giacomocavalieri/squirrel).
////

import gleam/dynamic/decode
import gleam/option.{type Option}
import gleam/time/timestamp.{type Timestamp}
import pog

/// Runs the `delete_session_by_token_hash` query
/// defined in `./src/server/sql/delete_session_by_token_hash.sql`.
///
/// > 🐿️ This function was generated automatically using v4.6.0 of
/// > the [squirrel package](https://github.com/giacomocavalieri/squirrel).
///
pub fn delete_session_by_token_hash(
  db: pog.Connection,
  arg_1: BitArray,
) -> Result(pog.Returned(Nil), pog.QueryError) {
  let decoder = decode.map(decode.dynamic, fn(_) { Nil })

  "DELETE FROM sessions
WHERE token_hash = $1;"
  |> pog.query
  |> pog.parameter(pog.bytea(arg_1))
  |> pog.returning(decoder)
  |> pog.execute(db)
}

/// Runs the `init_board` query
/// defined in `./src/server/sql/init_board.sql`.
///
/// > 🐿️ This function was generated automatically using v4.6.0 of
/// > the [squirrel package](https://github.com/giacomocavalieri/squirrel).
///
pub fn init_board(
  db: pog.Connection,
  arg_1: Int,
  arg_2: Int,
  arg_3: Int,
  arg_4: Int,
) -> Result(pog.Returned(Nil), pog.QueryError) {
  let decoder = decode.map(decode.dynamic, fn(_) { Nil })

  "WITH config AS (
  INSERT INTO board_config(width, height, max_color)
  VALUES ($1, $2, $3)
  RETURNING width, height
)
INSERT INTO board(x, y, color)
-- TODO: validate that initial_color is between 0 and max_color
SELECT x, y, $4
FROM config, generate_series(0, config.width - 1) AS x,
  generate_series(0, config.height - 1) AS y;"
  |> pog.query
  |> pog.parameter(pog.int(arg_1))
  |> pog.parameter(pog.int(arg_2))
  |> pog.parameter(pog.int(arg_3))
  |> pog.parameter(pog.int(arg_4))
  |> pog.returning(decoder)
  |> pog.execute(db)
}

/// Runs the `insert_session` query
/// defined in `./src/server/sql/insert_session.sql`.
///
/// > 🐿️ This function was generated automatically using v4.6.0 of
/// > the [squirrel package](https://github.com/giacomocavalieri/squirrel).
///
pub fn insert_session(
  db: pog.Connection,
  arg_1: BitArray,
  arg_2: Int,
  arg_3: Timestamp,
) -> Result(pog.Returned(Nil), pog.QueryError) {
  let decoder = decode.map(decode.dynamic, fn(_) { Nil })

  "INSERT INTO sessions(token_hash, user_id, expires_at)
VALUES ($1, $2, $3)"
  |> pog.query
  |> pog.parameter(pog.bytea(arg_1))
  |> pog.parameter(pog.int(arg_2))
  |> pog.parameter(pog.timestamp(arg_3))
  |> pog.returning(decoder)
  |> pog.execute(db)
}

/// A row you get from running the `insert_user` query
/// defined in `./src/server/sql/insert_user.sql`.
///
/// > 🐿️ This type definition was generated automatically using v4.6.0 of the
/// > [squirrel package](https://github.com/giacomocavalieri/squirrel).
///
pub type InsertUserRow {
  InsertUserRow(id: Int, email: String, username: String)
}

/// Runs the `insert_user` query
/// defined in `./src/server/sql/insert_user.sql`.
///
/// > 🐿️ This function was generated automatically using v4.6.0 of
/// > the [squirrel package](https://github.com/giacomocavalieri/squirrel).
///
pub fn insert_user(
  db: pog.Connection,
  arg_1: String,
  arg_2: String,
  arg_3: String,
) -> Result(pog.Returned(InsertUserRow), pog.QueryError) {
  let decoder = {
    use id <- decode.field(0, decode.int)
    use email <- decode.field(1, decode.string)
    use username <- decode.field(2, decode.string)
    decode.success(InsertUserRow(id:, email:, username:))
  }

  "insert into users(email, username, password_hash)
values ($1, $2, $3)
returning id, email, username"
  |> pog.query
  |> pog.parameter(pog.text(arg_1))
  |> pog.parameter(pog.text(arg_2))
  |> pog.parameter(pog.text(arg_3))
  |> pog.returning(decoder)
  |> pog.execute(db)
}

/// A row you get from running the `select_tile_info_by_xy` query
/// defined in `./src/server/sql/select_tile_info_by_xy.sql`.
///
/// > 🐿️ This type definition was generated automatically using v4.6.0 of the
/// > [squirrel package](https://github.com/giacomocavalieri/squirrel).
///
pub type SelectTileInfoByXyRow {
  SelectTileInfoByXyRow(updated_at: Timestamp, username: Option(String))
}

/// Runs the `select_tile_info_by_xy` query
/// defined in `./src/server/sql/select_tile_info_by_xy.sql`.
///
/// > 🐿️ This function was generated automatically using v4.6.0 of
/// > the [squirrel package](https://github.com/giacomocavalieri/squirrel).
///
pub fn select_tile_info_by_xy(
  db: pog.Connection,
  arg_1: Int,
  arg_2: Int,
) -> Result(pog.Returned(SelectTileInfoByXyRow), pog.QueryError) {
  let decoder = {
    use updated_at <- decode.field(0, pog.timestamp_decoder())
    use username <- decode.field(1, decode.optional(decode.string))
    decode.success(SelectTileInfoByXyRow(updated_at:, username:))
  }

  "SELECT b.updated_at, u.username
FROM board b
LEFT JOIN users u ON b.updated_by = u.id
WHERE b.x = $1 AND b.y = $2;"
  |> pog.query
  |> pog.parameter(pog.int(arg_1))
  |> pog.parameter(pog.int(arg_2))
  |> pog.returning(decoder)
  |> pog.execute(db)
}

/// A row you get from running the `select_user_by_session` query
/// defined in `./src/server/sql/select_user_by_session.sql`.
///
/// > 🐿️ This type definition was generated automatically using v4.6.0 of the
/// > [squirrel package](https://github.com/giacomocavalieri/squirrel).
///
pub type SelectUserBySessionRow {
  SelectUserBySessionRow(id: Int, email: String, username: String)
}

/// Runs the `select_user_by_session` query
/// defined in `./src/server/sql/select_user_by_session.sql`.
///
/// > 🐿️ This function was generated automatically using v4.6.0 of
/// > the [squirrel package](https://github.com/giacomocavalieri/squirrel).
///
pub fn select_user_by_session(
  db: pog.Connection,
  arg_1: BitArray,
  arg_2: Timestamp,
) -> Result(pog.Returned(SelectUserBySessionRow), pog.QueryError) {
  let decoder = {
    use id <- decode.field(0, decode.int)
    use email <- decode.field(1, decode.string)
    use username <- decode.field(2, decode.string)
    decode.success(SelectUserBySessionRow(id:, email:, username:))
  }

  "SELECT u.id, u.email, u.username
FROM sessions session
JOIN users u ON session.user_id = u.id
WHERE session.token_hash = $1
  AND session.expires_at > $2;"
  |> pog.query
  |> pog.parameter(pog.bytea(arg_1))
  |> pog.parameter(pog.timestamp(arg_2))
  |> pog.returning(decoder)
  |> pog.execute(db)
}

/// A row you get from running the `select_user_by_username` query
/// defined in `./src/server/sql/select_user_by_username.sql`.
///
/// > 🐿️ This type definition was generated automatically using v4.6.0 of the
/// > [squirrel package](https://github.com/giacomocavalieri/squirrel).
///
pub type SelectUserByUsernameRow {
  SelectUserByUsernameRow(
    id: Int,
    email: String,
    password_hash: String,
    username: String,
  )
}

/// Runs the `select_user_by_username` query
/// defined in `./src/server/sql/select_user_by_username.sql`.
///
/// > 🐿️ This function was generated automatically using v4.6.0 of
/// > the [squirrel package](https://github.com/giacomocavalieri/squirrel).
///
pub fn select_user_by_username(
  db: pog.Connection,
  arg_1: String,
) -> Result(pog.Returned(SelectUserByUsernameRow), pog.QueryError) {
  let decoder = {
    use id <- decode.field(0, decode.int)
    use email <- decode.field(1, decode.string)
    use password_hash <- decode.field(2, decode.string)
    use username <- decode.field(3, decode.string)
    decode.success(SelectUserByUsernameRow(
      id:,
      email:,
      password_hash:,
      username:,
    ))
  }

  "SELECT u.id, u.email, u.password_hash, u.username
FROM users u
WHERE u.username = $1;"
  |> pog.query
  |> pog.parameter(pog.text(arg_1))
  |> pog.returning(decoder)
  |> pog.execute(db)
}

/// Runs the `set_tile` query
/// defined in `./src/server/sql/set_tile.sql`.
///
/// > 🐿️ This function was generated automatically using v4.6.0 of
/// > the [squirrel package](https://github.com/giacomocavalieri/squirrel).
///
pub fn set_tile(
  db: pog.Connection,
  arg_1: Int,
  arg_2: Int,
  arg_3: Int,
  arg_4: Int,
) -> Result(pog.Returned(Nil), pog.QueryError) {
  let decoder = decode.map(decode.dynamic, fn(_) { Nil })

  "CALL set_tile($1, $2, $3, $4);"
  |> pog.query
  |> pog.parameter(pog.int(arg_1))
  |> pog.parameter(pog.int(arg_2))
  |> pog.parameter(pog.int(arg_3))
  |> pog.parameter(pog.int(arg_4))
  |> pog.returning(decoder)
  |> pog.execute(db)
}
