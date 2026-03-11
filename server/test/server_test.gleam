import fixture
import gleam/time/duration
import gleam/time/timestamp
import gleeunit
import server/auth

pub fn main() -> Nil {
  gleeunit.main()
}

pub fn signup_with_duplicate_email_test() {
  use conn <- fixture.with_connection()

  let assert Ok(_) =
    auth.signup(
      conn,
      email: "example@gmail.com",
      username: "example",
      password: "password123",
      session_expires_in: duration.seconds(10),
      now: timestamp.system_time(),
    )

  let assert Error(auth.EmailAlreadyExists) =
    auth.signup(
      conn,
      email: "example@gmail.com",
      username: "different_username",
      password: "password123",
      session_expires_in: duration.seconds(10),
      now: timestamp.system_time(),
    )
}

pub fn signup_with_duplicate_username_test() {
  use conn <- fixture.with_connection()

  let assert Ok(_) =
    auth.signup(
      conn,
      email: "example@gmail.com",
      username: "example",
      password: "password123",
      session_expires_in: duration.seconds(10),
      now: timestamp.system_time(),
    )

  let assert Error(auth.UsernameAlreadyExists) =
    auth.signup(
      conn,
      email: "different_email@gmail.com",
      username: "example",
      password: "password123",
      session_expires_in: duration.seconds(10),
      now: timestamp.system_time(),
    )
}

pub fn session_valid_test() {
  use conn <- fixture.with_connection()

  let assert Ok(#(created_user, session_token)) =
    auth.signup(
      conn,
      email: "example@gmail.com",
      username: "example",
      password: "password123",
      session_expires_in: duration.seconds(10),
      now: timestamp.system_time(),
    )

  let assert Ok(authenticated_user) =
    auth.authenticate(
      conn,
      session_token: session_token,
      now: timestamp.add(timestamp.system_time(), duration.seconds(5)),
    )

  assert created_user == authenticated_user
}

pub fn session_expired_test() {
  use conn <- fixture.with_connection()

  let assert Ok(#(_, session_token)) =
    auth.signup(
      conn,
      email: "example@gmail.com",
      username: "example",
      password: "password123",
      session_expires_in: duration.seconds(10),
      now: timestamp.system_time(),
    )

  let assert Error(auth.InvalidSession) =
    auth.authenticate(
      conn,
      session_token: session_token,
      now: timestamp.add(timestamp.system_time(), duration.seconds(50)),
    )
}

pub fn login_with_valid_session_test() {
  use conn <- fixture.with_connection()

  let now = timestamp.system_time()

  let assert Ok(#(_, signup_session_token)) =
    auth.signup(
      conn,
      email: "example@gmail.com",
      username: "example",
      password: "password123",
      session_expires_in: duration.seconds(1000),
      now: now,
    )

  let assert Ok(#(_, login_session_token)) =
    auth.login_with_session(
      conn,
      old_session_token: signup_session_token,
      expires_in: duration.seconds(10),
      now: now,
    )

  // makes sure new session is valid
  let assert Ok(_) =
    auth.authenticate(conn, session_token: login_session_token, now: now)

  // makes sure old session was fully replaced and no longer valid
  let assert Error(auth.InvalidSession) =
    auth.authenticate(conn, session_token: signup_session_token, now: now)
}

pub fn login_with_valid_credentials_test() {
  use conn <- fixture.with_connection()

  let now = timestamp.system_time()

  let assert Ok(#(created_user, _)) =
    auth.signup(
      conn,
      email: "example@gmail.com",
      username: "example",
      password: "password123",
      session_expires_in: duration.seconds(1000),
      now: now,
    )

  let assert Ok(#(authenticated_user, session_token)) =
    auth.login_with_credentials(
      conn,
      username: "example",
      password: "password123",
      session_expires_in: duration.seconds(10),
      now: now,
    )

  assert created_user == authenticated_user

  let assert Ok(_) =
    auth.authenticate(conn, session_token: session_token, now: now)
}

pub fn login_with_invalid_credentials_test() {
  use conn <- fixture.with_connection()

  let now = timestamp.system_time()

  let assert Ok(_) =
    auth.signup(
      conn,
      email: "example@gmail.com",
      username: "example",
      password: "password123",
      session_expires_in: duration.seconds(1000),
      now: now,
    )

  let assert Error(auth.InvalidCredentials) =
    auth.login_with_credentials(
      conn,
      username: "wrong_username",
      password: "password123",
      session_expires_in: duration.seconds(10),
      now: now,
    )

  let assert Error(auth.InvalidCredentials) =
    auth.login_with_credentials(
      conn,
      username: "example",
      password: "wrong_password",
      session_expires_in: duration.seconds(10),
      now: now,
    )
}
// pub fn login_integration_test() {
//   let body = [#("username", "example"), #("password", "password123")]

//   let request =
//     simulate.request(http.Post, "/api/login") |> simulate.form_body(body)

//   use conn <- fixture.with_connection()
//   let ctx = Context(db: conn)

//   let response_body =
//     request |> router.handle_request(ctx) |> simulate.read_body
// }
