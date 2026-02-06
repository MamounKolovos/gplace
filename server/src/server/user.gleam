import gleam/json.{type Json}
import gleam/result
import gleam/time/timestamp.{type Timestamp}
import pog
import server/database
import server/error.{type Error}
import server/sql

pub type User {
  User(
    id: Int,
    email: String,
    username: String,
    created_at: Timestamp,
    updated_at: Timestamp,
  )
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
) -> Result(User, Error(f)) {
  database.insert_user(db, email, username, password_hash)
  |> result.map(from_insert_user_row)
}

pub fn from_select_user_by_username_row(
  row: sql.SelectUserByUsernameRow,
) -> User {
  User(
    id: row.id,
    email: row.email,
    username: row.username,
    created_at: row.created_at,
    updated_at: row.updated_at,
  )
}

pub fn from_select_user_by_session_row(row: sql.SelectUserBySessionRow) -> User {
  User(
    id: row.id,
    email: row.email,
    username: row.username,
    created_at: row.created_at,
    updated_at: row.updated_at,
  )
}

pub fn from_insert_user_row(row: sql.InsertUserRow) -> User {
  User(
    id: row.id,
    email: row.email,
    username: row.username,
    created_at: row.created_at,
    updated_at: row.updated_at,
  )
}
