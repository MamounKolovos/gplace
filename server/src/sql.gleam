//// This module contains the code to run the sql queries defined in
//// `./src/sql`.
//// > 🐿️ This module was generated automatically using v4.6.0 of
//// > the [squirrel package](https://github.com/giacomocavalieri/squirrel).
////

import gleam/dynamic/decode
import gleam/time/timestamp.{type Timestamp}
import pog

/// A row you get from running the `insert_user` query
/// defined in `./src/sql/insert_user.sql`.
///
/// > 🐿️ This type definition was generated automatically using v4.6.0 of the
/// > [squirrel package](https://github.com/giacomocavalieri/squirrel).
///
pub type InsertUserRow {
  InsertUserRow(
    id: Int,
    email: String,
    name: String,
    created_at: Timestamp,
    updated_at: Timestamp,
  )
}

/// Runs the `insert_user` query
/// defined in `./src/sql/insert_user.sql`.
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
    use name <- decode.field(2, decode.string)
    use created_at <- decode.field(3, pog.timestamp_decoder())
    use updated_at <- decode.field(4, pog.timestamp_decoder())
    decode.success(InsertUserRow(id:, email:, name:, created_at:, updated_at:))
  }

  "insert into users(email, name, password_hash)
values ($1, $2, $3)
returning id, email, name, created_at, updated_at"
  |> pog.query
  |> pog.parameter(pog.text(arg_1))
  |> pog.parameter(pog.text(arg_2))
  |> pog.parameter(pog.text(arg_3))
  |> pog.returning(decoder)
  |> pog.execute(db)
}
