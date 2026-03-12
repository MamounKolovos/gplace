import gleam/bool
import gleam/crypto
import gleam/option.{None, Some}
import gleam/result
import gleam/time/duration.{type Duration}
import gleam/time/timestamp.{type Timestamp}
import pog
import server/database
import server/user.{type User}
import youid/uuid.{type Uuid}

pub type Error {
  // HashingFailed(argus.HashError)
  EmailAlreadyExists
  UsernameAlreadyExists
  InvalidCredentials
  InvalidSession
  InternalError(database.Error)
}

fn from_database_error(error: database.Error) -> Error {
  case error {
    database.QueryFailed(pog.ConstraintViolated(
      message: _,
      constraint:,
      detail: _,
    )) as error ->
      case constraint {
        "users_email_key" -> EmailAlreadyExists
        "users_username_key" -> UsernameAlreadyExists
        _ -> InternalError(error)
      }
    error -> InternalError(error)
  }
}

pub fn authenticate(
  db db: pog.Connection,
  session_token session_token: Uuid,
  now now: Timestamp,
) -> Result(User, Error) {
  let token_hash =
    session_token
    |> uuid.to_bit_array
    |> crypto.hash(crypto.Sha256, _)

  case database.select_user_by_session(db, token_hash: token_hash, now: now) {
    Ok(Some(row)) -> row |> user.from_select_user_by_session_row |> Ok
    // session not found or session expired
    Ok(None) -> Error(InvalidSession)
    Error(error) -> Error(InternalError(error))
  }
}

pub fn signup(
  db db: pog.Connection,
  email email: String,
  username username: String,
  password password: String,
  session_expires_in duration: Duration,
  now now: Timestamp,
) -> Result(#(User, Uuid), Error) {
  // use hashes <- result.try(
  //   argus.hasher()
  //   |> argus.hash_length(12)
  //   |> argus.hash(password, argus.gen_salt())
  //   |> result.map_error(HashFailure),
  // )
  use user <- result.try(
    user.insert(
      db,
      email: email,
      username: username,
      // TEMPORARY until jargon adds windows support
      password_hash: password,
    )
    |> result.map_error(from_database_error),
  )

  use session_token <- result.try(insert_session(
    db,
    for: user,
    at: now,
    expires_in: duration,
  ))

  Ok(#(user, session_token))
}

pub fn login_with_session(
  db db: pog.Connection,
  old_session_token token: Uuid,
  expires_in duration: Duration,
  now now: Timestamp,
) -> Result(#(User, Uuid), Error) {
  use user <- result.try(authenticate(db, session_token: token, now: now))

  use token <- result.try(refresh_session(
    db,
    for: user,
    old_token: token,
    at: now,
    expires_in: duration,
  ))

  Ok(#(user, token))
}

pub fn login_with_credentials(
  db db: pog.Connection,
  username username: String,
  password password: String,
  session_expires_in duration: Duration,
  now now: Timestamp,
) -> Result(#(User, Uuid), Error) {
  use row <- result.try(
    case database.select_user_by_username(db, username: username) {
      Ok(Some(row)) -> Ok(row)
      Ok(None) -> Error(InvalidCredentials)
      Error(error) -> Error(InternalError(error))
    },
  )

  // use hashes <- result.try(
  //   argus.hasher()
  //   |> argus.hash_length(12)
  //   |> argus.hash(password, argus.gen_salt())
  //   |> result.map_error(HashFailure),
  // )

  use <- bool.guard(
    password != row.password_hash,
    return: Error(InvalidCredentials),
  )

  let user = row |> user.from_select_user_by_username_row

  use session_token <- result.try(insert_session(
    db,
    for: user,
    at: now,
    expires_in: duration,
  ))

  Ok(#(user, session_token))
}

fn refresh_session(
  db db: pog.Connection,
  for user: User,
  old_token token: Uuid,
  at now: Timestamp,
  expires_in duration: Duration,
) -> Result(Uuid, Error) {
  let token_hash = token |> uuid.to_bit_array |> crypto.hash(crypto.Sha256, _)

  use _ <- result.try(
    database.delete_session_by_token_hash(db, token_hash: token_hash)
    |> result.map_error(from_database_error),
  )

  use token <- result.try(insert_session(
    db,
    for: user,
    at: now,
    expires_in: duration,
  ))

  Ok(token)
}

fn insert_session(
  db db: pog.Connection,
  for user: User,
  at now: Timestamp,
  expires_in duration: Duration,
) -> Result(Uuid, Error) {
  let session_token = uuid.v4()
  let token_hash =
    session_token |> uuid.to_bit_array |> crypto.hash(crypto.Sha256, _)

  let expires_at = timestamp.add(now, duration)

  use _ <- result.try(
    database.insert_session(
      db,
      token_hash: token_hash,
      user_id: user.id,
      expires_at: expires_at,
    )
    |> result.map_error(from_database_error),
  )

  Ok(session_token)
}
