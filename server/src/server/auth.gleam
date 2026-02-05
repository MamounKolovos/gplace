import gleam/crypto
import gleam/result
import gleam/time/duration.{type Duration}
import gleam/time/timestamp.{type Timestamp}
import pog
import server/database
import server/error.{type Error}
import server/user.{type User}
import server/web.{type Context}
import youid/uuid.{type Uuid}

pub fn authenticate(
  db db: pog.Connection,
  session_token session_token: Uuid,
  now now: Timestamp,
) -> Result(User, Error(f)) {
  let token_hash =
    session_token
    |> uuid.to_bit_array
    |> crypto.hash(crypto.Sha256, _)

  database.select_user_by_session(db, token_hash: token_hash, now: now)
  |> result.map(user.from_select_user_by_session_row)
}

pub fn signup(
  db db: pog.Connection,
  email email: String,
  username username: String,
  password password: String,
  session_expires_in duration: Duration,
) -> Result(#(User, Uuid), Error(f)) {
  // use hashes <- result.try(
  //   argus.hasher()
  //   |> argus.hash_length(12)
  //   |> argus.hash(password, argus.gen_salt())
  //   |> result.map_error(HashFailure),
  // )
  use user <- result.try(user.insert(
    db,
    email: email,
    username: username,
    // TEMPORARY until jargon adds windows support
    password_hash: password,
  ))

  use session_token <- result.try(insert_session(
    db,
    for: user,
    expires_in: duration,
  ))

  Ok(#(user, session_token))
}

fn insert_session(
  db db: pog.Connection,
  for user: User,
  expires_in duration: Duration,
) -> Result(Uuid, Error(f)) {
  let session_token = uuid.v4()
  let token_hash =
    session_token |> uuid.to_bit_array |> crypto.hash(crypto.Sha256, _)

  let expires_at = timestamp.add(timestamp.system_time(), duration)

  use _ <- result.try(database.insert_session(
    db,
    token_hash: token_hash,
    user_id: user.id,
    expires_at: expires_at,
  ))

  Ok(session_token)
}
