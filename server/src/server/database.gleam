import gleam/option.{type Option, None, Some}
import gleam/result
import gleam/time/timestamp.{type Timestamp}
import pog
import server/sql

pub type Error {
  QueryFailed(pog.QueryError)
  UnexpectedQueryResult
}

pub fn insert_session(
  db db: pog.Connection,
  token_hash token_hash: BitArray,
  user_id user_id: Int,
  expires_at expires_at: Timestamp,
) -> Result(Nil, Error) {
  sql.insert_session(db, token_hash, user_id, expires_at) |> zero
}

pub fn insert_user(
  db db: pog.Connection,
  email email: String,
  username username: String,
  password_hash password_hash: String,
) -> Result(sql.InsertUserRow, Error) {
  sql.insert_user(db, email, username, password_hash) |> one
}

pub fn select_user_by_session(
  db db: pog.Connection,
  token_hash token_hash: BitArray,
  now now: Timestamp,
) -> Result(Option(sql.SelectUserBySessionRow), Error) {
  sql.select_user_by_session(db, token_hash, now) |> maybe_one
}

pub fn select_user_by_username(
  db db: pog.Connection,
  username username: String,
) -> Result(Option(sql.SelectUserByUsernameRow), Error) {
  sql.select_user_by_username(db, username) |> maybe_one
}

pub fn delete_session_by_token_hash(
  db db: pog.Connection,
  token_hash token_hash: BitArray,
) -> Result(Nil, Error) {
  sql.delete_session_by_token_hash(db, token_hash) |> zero
}

pub fn init_board(
  db: pog.Connection,
  width width: Int,
  height height: Int,
  max_color max_color: Int,
  initial_color initial_color: Int,
) -> Result(Nil, Error) {
  sql.init_board(db, width, height, max_color, initial_color) |> zero
}

pub fn init_random_board(
  db: pog.Connection,
  width width: Int,
  height height: Int,
  max_color max_color: Int,
) -> Result(Nil, Error) {
  sql.init_random_board(db, width, height, max_color) |> zero
}

pub fn set_tile(
  db: pog.Connection,
  x x: Int,
  y y: Int,
  color color: Int,
  user_id user_id: Int,
) -> Result(Nil, Error) {
  sql.set_tile(db, x, y, color, user_id) |> zero
}

pub fn set_tiles(
  db: pog.Connection,
  xs xs: List(Int),
  ys ys: List(Int),
  colors colors: List(Int),
  user_ids user_ids: List(Int),
) -> Result(Nil, Error) {
  sql.set_tiles(db, xs, ys, colors, user_ids) |> zero
}

pub fn select_tile_info_by_xy(
  db: pog.Connection,
  x x: Int,
  y y: Int,
) -> Result(sql.SelectTileInfoByXyRow, Error) {
  sql.select_tile_info_by_xy(db, x, y) |> one
}

pub fn select_board(
  db: pog.Connection,
) -> Result(List(sql.SelectBoardRow), Error) {
  sql.select_board(db) |> many
}

pub fn truncate_all(db: pog.Connection) -> Result(Nil, Error) {
  sql.truncate_all(db) |> zero
}

fn many(
  query_result: Result(pog.Returned(row), pog.QueryError),
) -> Result(List(row), Error) {
  use returned <- result.try(query_result |> result.map_error(QueryFailed))
  Ok(returned.rows)
}

fn one(
  query_result: Result(pog.Returned(row), pog.QueryError),
) -> Result(row, Error) {
  use returned <- result.try(query_result |> result.map_error(QueryFailed))
  case returned.rows {
    [row] -> Ok(row)
    _ -> Error(UnexpectedQueryResult)
  }
}

fn maybe_one(
  query_result: Result(pog.Returned(row), pog.QueryError),
) -> Result(Option(row), Error) {
  use returned <- result.try(query_result |> result.map_error(QueryFailed))

  case returned.rows {
    [row] -> Ok(Some(row))
    [] -> Ok(None)
    _ -> Error(UnexpectedQueryResult)
  }
}

fn zero(
  query_result: Result(pog.Returned(Nil), pog.QueryError),
) -> Result(Nil, Error) {
  case query_result {
    Ok(_) -> Ok(Nil)
    Error(error) -> Error(QueryFailed(error))
  }
}
