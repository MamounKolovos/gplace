import argus
import formal/form.{type Form}
import gleam/bit_array
import gleam/crypto
import gleam/dynamic/decode
import gleam/float
import gleam/int
import gleam/json.{type Json}
import gleam/list
import gleam/option.{None, Some}
import gleam/result
import gleam/time/duration.{type Duration}
import gleam/time/timestamp.{type Timestamp}
import pog
import server/auth
import server/sql
import server/user
import server/web.{type Context}
import shared/api_error.{type ApiError, ApiError}
import wisp.{type Request, type Response}
import youid/uuid

const session_duration_seconds = 3600

type Error(f) {
  InvalidForm(Form(f))
  AuthError(auth.Error)
  SessionParsingFailed
}

pub fn handle_request(request: Request, ctx: Context) -> Response {
  use request <- web.middleware(request)
  case wisp.path_segments(request) {
    ["api", "signup"] -> signup(request, ctx)
    ["api", "login"] -> login(request, ctx)
    ["api", "me"] -> me(request, ctx)
    ["api", "board"] -> board(request, ctx)
    _ -> wisp.not_found()
  }
}

pub type Snapshot {
  Snapshot(color_indexes: BitArray, width: Int, height: Int)
}

fn snapshot_to_json(snapshot: Snapshot) -> Json {
  let Snapshot(color_indexes:, width:, height:) = snapshot
  json.object([
    #(
      "color_indexes",
      color_indexes |> bit_array.base64_encode(True) |> json.string,
    ),
    #("width", json.int(width)),
    #("height", json.int(height)),
  ])
}

fn board(request: wisp.Request, ctx: Context) -> wisp.Response {
  let color_indexes =
    int.range(0, 999_999, with: [], run: list.prepend)
    |> list.map(fn(_) { int.random(16) })
    |> list.fold(from: <<>>, with: fn(acc, n) { <<acc:bits, n:4>> })
  let width = 1000
  let height = 1000

  Snapshot(color_indexes:, width:, height:)
  |> snapshot_to_json
  |> json.to_string
  |> wisp.json_response(200)
}

fn me(request: wisp.Request, ctx: Context) -> wisp.Response {
  let result = {
    use session_token_string <- result.try(
      request
      |> wisp.get_cookie("session", wisp.PlainText)
      |> result.replace_error(SessionParsingFailed),
    )

    use session_token <- result.try(
      session_token_string
      |> uuid.from_string
      |> result.replace_error(SessionParsingFailed),
    )

    auth.authenticate(
      ctx.db,
      session_token: session_token,
      now: timestamp.system_time(),
    )
    |> result.map_error(AuthError)
  }

  case result {
    Ok(user) ->
      user |> user.to_json |> json.to_string |> wisp.json_response(200)
    Error(SessionParsingFailed) -> unauthenticated()
    Error(AuthError(auth.InvalidSession)) -> unauthenticated()
    Error(_) -> internal_error()
  }
}

fn login(request: wisp.Request, ctx: Context) -> wisp.Response {
  use form_data <- wisp.require_form(request)
  let form = login_form() |> form.add_values(form_data.values)

  let result = case form.run(form) {
    Ok(login_data) -> {
      // convert to option because `None` just indicates that we need to do normal login logic
      // `Some` would mean the token exists and we can check its validity to see if we can short circuit
      let session_token =
        request
        |> wisp.get_cookie("session", wisp.PlainText)
        |> result.try(uuid.from_string)
        |> option.from_result

      let now = timestamp.system_time()
      let session_duration = duration.seconds(session_duration_seconds)

      case session_token {
        Some(session_token) -> {
          let result =
            auth.login_with_session(
              ctx.db,
              old_session_token: session_token,
              expires_in: session_duration,
              now: now,
            )

          case result {
            Ok(result) -> Ok(result)
            Error(auth.InvalidSession) ->
              auth.login_with_credentials(
                ctx.db,
                username: login_data.username,
                password: login_data.password,
                session_expires_in: session_duration,
                now: now,
              )
              |> result.map_error(AuthError)
            Error(error) -> Error(AuthError(error))
          }
        }
        None ->
          auth.login_with_credentials(
            ctx.db,
            username: login_data.username,
            password: login_data.password,
            session_expires_in: session_duration,
            now: now,
          )
          |> result.map_error(AuthError)
      }
    }
    Error(form) -> Error(InvalidForm(form))
  }

  case result {
    Ok(#(user, session_token)) ->
      user
      |> user.to_json
      |> json.to_string
      |> wisp.json_response(200)
      |> wisp.set_cookie(
        request,
        name: "session",
        value: uuid.to_string(session_token),
        security: wisp.PlainText,
        max_age: session_duration_seconds,
      )
    Error(AuthError(auth.InvalidCredentials)) -> invalid_credentials()
    Error(InvalidForm(form)) -> invalid_form("Some fields are invalid")
    Error(_) -> internal_error()
  }
}

type Login {
  Login(username: String, password: String)
}

fn login_form() -> Form(Login) {
  form.new({
    use username <- form.field(
      "username",
      form.parse_string |> form.check_not_empty,
    )
    use password <- form.field(
      "password",
      form.parse_string
        |> form.check_not_empty
        |> form.check_string_length_more_than(8),
    )

    form.success(Login(username:, password:))
  })
}

fn signup(request: wisp.Request, ctx: Context) -> wisp.Response {
  use form_data <- wisp.require_form(request)
  let form = signup_form() |> form.add_values(form_data.values)

  let result = case form.run(form) {
    Ok(signup) -> {
      auth.signup(
        ctx.db,
        email: signup.email,
        username: signup.username,
        password: signup.password,
        session_expires_in: duration.seconds(session_duration_seconds),
        now: timestamp.system_time(),
      )
      |> result.map_error(AuthError)
    }
    Error(form) -> Error(InvalidForm(form))
  }

  case result {
    Ok(#(user, session_token)) ->
      user
      |> user.to_json
      |> json.to_string
      |> wisp.json_response(201)
      |> wisp.set_cookie(
        request,
        name: "session",
        value: uuid.to_string(session_token),
        security: wisp.PlainText,
        max_age: session_duration_seconds,
      )
    Error(InvalidForm(form)) -> invalid_form("Some fields are invalid")
    Error(AuthError(auth.EmailAlreadyExists)) ->
      duplicate_identifier("Email is already in use")
    Error(AuthError(auth.UsernameAlreadyExists)) ->
      duplicate_identifier("Username is taken")
    Error(_) -> internal_error()
  }
}

fn api_error_code_to_json(code: api_error.Code) -> Json {
  case code {
    api_error.InvalidForm -> "INVALID_FORM"
    api_error.InternalError -> "INTERNAL_ERROR"
    api_error.Unauthenticated -> "UNAUTHENTICATED"
    api_error.InvalidCredentials -> "INVALID_CREDENTIALS"
    api_error.DuplicateIdentifier -> "DUPLICATE_IDENTIFIER"
  }
  |> json.string
}

fn api_error_code_status(code: api_error.Code) -> Int {
  case code {
    api_error.InvalidForm -> 400
    api_error.InternalError -> 500
    api_error.Unauthenticated -> 401
    api_error.InvalidCredentials -> 401
    api_error.DuplicateIdentifier -> 409
  }
}

fn invalid_form(message: String) -> Response {
  ApiError(code: api_error.InvalidForm, message: message)
  |> api_error_response
}

fn internal_error() -> Response {
  ApiError(code: api_error.InternalError, message: "Internal server error")
  |> api_error_response
}

fn unauthenticated() -> Response {
  ApiError(code: api_error.Unauthenticated, message: "Not authenticated")
  |> api_error_response
}

fn invalid_credentials() -> Response {
  ApiError(
    code: api_error.InvalidCredentials,
    message: "Username or password is incorrect",
  )
  |> api_error_response
}

fn duplicate_identifier(message: String) -> Response {
  ApiError(code: api_error.DuplicateIdentifier, message: message)
  |> api_error_response
}

fn api_error_response(api_error: ApiError) -> Response {
  let status = api_error_code_status(api_error.code)
  api_error |> api_error_to_json |> json.to_string |> wisp.json_response(status)
}

fn api_error_to_json(api_error: ApiError) -> Json {
  json.object([
    #(
      "error",
      json.object([
        #("code", api_error_code_to_json(api_error.code)),
        #("message", json.string(api_error.message)),
      ]),
    ),
  ])
}

pub type Signup {
  Signup(email: String, username: String, password: String)
}

fn signup_form() -> Form(Signup) {
  form.new({
    use email <- form.field("email", form.parse_email)
    use username <- form.field(
      "username",
      form.parse_string |> form.check_not_empty,
    )
    use password <- form.field(
      "password",
      form.parse_string
        |> form.check_not_empty
        |> form.check_string_length_more_than(8),
    )

    form.success(Signup(email:, username:, password:))
  })
}
