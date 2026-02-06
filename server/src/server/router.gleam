import argus
import formal/form.{type Form}
import gleam/bit_array
import gleam/crypto
import gleam/dynamic/decode
import gleam/float
import gleam/json.{type Json}
import gleam/list
import gleam/option.{None, Some}
import gleam/result
import gleam/time/duration.{type Duration}
import gleam/time/timestamp.{type Timestamp}
import pog
import server/auth
import server/error.{type Error}
import server/sql
import server/user
import server/web.{type Context}
import shared
import wisp.{type Request, type Response}
import youid/uuid

const session_duration_seconds = 3600

pub fn handle_request(request: Request, ctx: Context) -> Response {
  use request <- web.middleware(request)
  case wisp.path_segments(request) {
    ["api", "signup"] -> signup(request, ctx)
    ["api", "login"] -> login(request, ctx)
    ["api", "me"] -> me(request, ctx)
    _ -> wisp.not_found()
  }
}

fn me(request: wisp.Request, ctx: Context) -> wisp.Response {
  let result = {
    use session_token_string <- result.try(
      request
      |> wisp.get_cookie("session", wisp.PlainText)
      |> result.replace_error(error.InvalidSession(
        "no session present in cookies",
      )),
    )

    use session_token <- result.try(
      session_token_string
      |> uuid.from_string
      |> result.replace_error(error.InvalidSession(
        "session cookie is not a valid uuid",
      )),
    )

    auth.authenticate(
      ctx.db,
      session_token: session_token,
      now: timestamp.system_time(),
    )
  }

  case result {
    Ok(user) ->
      user |> user.to_json |> json.to_string |> wisp.json_response(200)
    Error(error.InvalidSession(reason:)) -> {
      wisp.log_error(reason)
      unauthorized()
    }
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

      auth.login(
        ctx.db,
        username: login_data.username,
        password: login_data.password,
        session_token: session_token,
        session_expires_in: duration.seconds(session_duration_seconds),
        now: timestamp.system_time(),
      )
    }
    Error(form) -> Error(error.InvalidForm(form))
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
    Error(error.InvalidCredentials) -> invalid_credentials()
    Error(error.InvalidQuery(error)) -> internal_error()
    Error(error.UnexpectedQueryResult) -> internal_error()
    Error(error.InvalidForm(form)) -> invalid_form("Some fields are invalid")
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
      )
    }
    Error(form) -> Error(error.InvalidForm(form))
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
    Error(error.InvalidQuery(error)) -> internal_error()
    Error(error.UnexpectedQueryResult) -> internal_error()
    Error(error.InvalidForm(form)) -> invalid_form("Some fields are invalid")
    Error(_) -> internal_error()
  }
}

fn api_error_code_to_json(code: shared.ApiErrorCode) -> Json {
  case code {
    shared.InvalidFormCode -> "INVALID_FORM"
    shared.InternalError -> "INTERNAL_ERROR"
    shared.Unauthorized -> "UNAUTHORIZED"
    shared.InvalidCredentials -> "INVALID_CREDENTIALS"
  }
  |> json.string
}

fn api_error_code_status(code: shared.ApiErrorCode) -> Int {
  case code {
    shared.InvalidFormCode -> 400
    shared.InternalError -> 500
    shared.Unauthorized -> 401
    shared.InvalidCredentials -> 401
  }
}

fn invalid_form(message: String) -> Response {
  shared.ApiError(code: shared.InvalidFormCode, message: message)
  |> api_error_response
}

fn internal_error() -> Response {
  shared.ApiError(code: shared.InternalError, message: "Internal server error")
  |> api_error_response
}

fn unauthorized() -> Response {
  shared.ApiError(code: shared.Unauthorized, message: "Not authenticated")
  |> api_error_response
}

fn invalid_credentials() -> Response {
  shared.ApiError(
    code: shared.InvalidCredentials,
    message: "Username or password is incorrect",
  )
  |> api_error_response
}

fn api_error_response(api_error: shared.ApiError) -> Response {
  let status = api_error_code_status(api_error.code)
  api_error |> api_error_to_json |> json.to_string |> wisp.json_response(status)
}

fn api_error_to_json(api_error: shared.ApiError) -> Json {
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
