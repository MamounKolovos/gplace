import gleam/crypto
import gleam/json.{type Json}
import gleam/option.{type Option, None, Some}
import gleam/result
import gleam/time/timestamp.{type Timestamp}
import pog
import server/database
import server/sql
import youid/uuid.{type Uuid}

pub type Error {
  InternalError(database.Error)
}

pub type User {
  User(id: Int, email: String, username: String)
}

pub fn to_json(user: User) -> Json {
  json.object([
    #("id", json.int(user.id)),
    #("username", json.string(user.username)),
  ])
}

pub fn insert(
  db db: pog.Connection,
  email email: String,
  username username: String,
  password_hash password_hash: String,
) -> Result(User, database.Error) {
  database.insert_user(db, email, username, password_hash)
  |> result.map(from_insert_user_row)
}

pub type Stats {
  Stats(tiles_placed: Int, last_placed_at: Option(Timestamp))
}

pub fn get_stats(user: User, db: pog.Connection) -> Result(Stats, Error) {
  use row <- result.try(
    database.select_stats_by_id(db, id: user.id)
    |> result.map_error(InternalError),
  )

  Stats(tiles_placed: row.tiles_placed, last_placed_at: row.last_placed_at)
  |> Ok
}

pub fn get_last_placed_at(
  user: User,
  db: pog.Connection,
) -> Result(Option(Timestamp), Error) {
  use row <- result.try(
    database.select_last_placed_at_by_id(db, id: user.id)
    |> result.map_error(InternalError),
  )

  Ok(row.last_placed_at)
}

pub fn from_select_user_by_username_row(
  row: sql.SelectUserByUsernameRow,
) -> User {
  User(id: row.id, email: row.email, username: row.username)
}

pub fn from_select_user_by_session_row(row: sql.SelectUserBySessionRow) -> User {
  User(id: row.id, email: row.email, username: row.username)
}

pub fn from_insert_user_row(row: sql.InsertUserRow) -> User {
  User(id: row.id, email: row.email, username: row.username)
}
