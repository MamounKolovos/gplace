import gleam/option.{type Option, None, Some}
import gleam/result
import gleam/time/timestamp.{type Timestamp}
import pog
import server/error.{type Error}
import server/sql

pub fn insert_session(
  db db: pog.Connection,
  token_hash token_hash: BitArray,
  user_id user_id: Int,
  expires_at expires_at: Timestamp,
) -> Result(Nil, Error(f)) {
  sql.insert_session(db, token_hash, user_id, expires_at) |> zero
}

pub fn insert_user(
  db db: pog.Connection,
  email email: String,
  username username: String,
  password_hash password_hash: String,
) -> Result(sql.InsertUserRow, Error(f)) {
  sql.insert_user(db, email, username, password_hash) |> one
}

pub fn select_user_by_session(
  db db: pog.Connection,
  token_hash token_hash: BitArray,
  now now: Timestamp,
) -> Result(sql.SelectUserBySessionRow, Error(f)) {
  use option <- result.try(
    sql.select_user_by_session(db, token_hash, now) |> maybe_one,
  )

  case option {
    Some(row) -> Ok(row)
    None -> Error(error.InvalidSession("session expired or session not found"))
  }
}

pub fn select_user_by_username(
  db db: pog.Connection,
  username username: String,
) -> Result(Option(sql.SelectUserByUsernameRow), Error(f)) {
  sql.select_user_by_username(db, username) |> maybe_one
}

pub fn delete_session_by_token_hash(
  db db: pog.Connection,
  token_hash token_hash: BitArray,
) -> Result(Nil, Error(f)) {
  sql.delete_session_by_token_hash(db, token_hash) |> zero
}

fn one(
  query_result: Result(pog.Returned(row), pog.QueryError),
) -> Result(row, Error(f)) {
  use returned <- result.try(
    query_result |> result.map_error(error.InvalidQuery),
  )
  case returned.rows {
    [row] -> Ok(row)
    _ -> Error(error.UnexpectedQueryResult)
  }
}

fn maybe_one(
  query_result: Result(pog.Returned(row), pog.QueryError),
) -> Result(Option(row), Error(f)) {
  use returned <- result.try(
    query_result |> result.map_error(error.InvalidQuery),
  )

  case returned.rows {
    [row] -> Ok(Some(row))
    [] -> Ok(None)
    _ -> Error(error.UnexpectedQueryResult)
  }
}

fn zero(
  query_result: Result(pog.Returned(Nil), pog.QueryError),
) -> Result(Nil, Error(f)) {
  case query_result {
    Ok(_) -> Ok(Nil)
    Error(error) -> Error(error.InvalidQuery(error))
  }
}
