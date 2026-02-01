import argus
import formal/form.{type Form}
import gleam/crypto
import gleam/float
import gleam/json.{type Json}
import gleam/list
import gleam/result
import gleam/time/duration.{type Duration}
import gleam/time/timestamp.{type Timestamp}
import pog
import shared
import sql
import web.{type Context}
import wisp.{type Request, type Response}
import youid/uuid

const session_duration_seconds = 3600

pub fn handle_request(request: Request, ctx: Context) -> Response {
  use request <- web.middleware(request)
  case wisp.path_segments(request) {
    ["api", "signup"] -> signup(request, ctx)
    _ -> wisp.not_found()
  }
}

type Error {
  // HashFailure(argus.HashError)
  InvalidQuery(pog.QueryError)
  UnexpectedQueryResult
  InvalidForm(Form(Signup))
}

fn signup(request: wisp.Request, ctx: Context) -> wisp.Response {
  use form_data <- wisp.require_form(request)
  let form = signup_form() |> form.add_values(form_data.values)

  let result = case form.run(form) {
    Ok(signup) -> {
      // use hashes <- result.try(
      //   argus.hasher()
      //   |> argus.hash_length(12)
      //   |> argus.hash(signup.password, argus.gen_salt())
      //   |> result.map_error(HashFailure),
      // )
      // use returned <- result.try(
      //   sql.insert_user(
      //     ctx.conn,
      //     signup.email,
      //     signup.username,
      //     hashes.encoded_hash,
      //   )
      //   |> result.map_error(InvalidQuery),
      // )
      use insert_user_row <- result.try(
        // TEMPORARY until jargon adds windows support
        sql.insert_user(ctx.db, signup.email, signup.username, signup.password)
        |> one,
      )

      let user = insert_user_row_to_user(insert_user_row)

      let expires_at =
        timestamp.add(
          timestamp.system_time(),
          duration.seconds(session_duration_seconds),
        )

      let session_token = uuid.v4()
      let token_hash =
        session_token |> uuid.to_bit_array |> crypto.hash(crypto.Sha256, _)

      use _ <- result.try(
        sql.insert_session(ctx.db, token_hash, user.id, expires_at)
        |> zero,
      )

      Ok(#(user, session_token))
    }
    Error(form) -> Error(InvalidForm(form))
  }

  case result {
    Ok(#(user, session_token)) ->
      user
      |> user_to_json
      |> json.to_string
      |> wisp.json_response(201)
      |> wisp.set_cookie(
        request,
        name: "session",
        value: uuid.to_string(session_token),
        security: wisp.PlainText,
        max_age: session_duration_seconds,
      )
    Error(InvalidQuery(error)) -> internal_error()
    Error(UnexpectedQueryResult) -> internal_error()
    Error(InvalidForm(form)) -> invalid_form("Some fields are invalid")
  }
}

fn one(
  query_result: Result(pog.Returned(row), pog.QueryError),
) -> Result(row, Error) {
  use returned <- result.try(query_result |> result.map_error(InvalidQuery))
  use row <- result.try(
    returned.rows |> list.first |> result.replace_error(UnexpectedQueryResult),
  )
  Ok(row)
}

fn zero(
  query_result: Result(pog.Returned(Nil), pog.QueryError),
) -> Result(Nil, Error) {
  case query_result {
    Ok(_) -> Ok(Nil)
    Error(error) -> Error(InvalidQuery(error))
  }
}

fn api_error_code_to_json(code: shared.ApiErrorCode) -> Json {
  case code {
    shared.InvalidFormCode -> "INVALID_FORM"
    shared.InternalError -> "INTERNAL_ERROR"
  }
  |> json.string
}

fn api_error_code_status(code: shared.ApiErrorCode) -> Int {
  case code {
    shared.InvalidFormCode -> 400
    shared.InternalError -> 500
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

type User {
  User(
    id: Int,
    email: String,
    username: String,
    created_at: Timestamp,
    updated_at: Timestamp,
  )
}

fn user_to_json(user: User) -> Json {
  json.object([
    #("id", json.int(user.id)),
    #("username", json.string(user.username)),
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

fn insert_user_row_to_user(row: sql.InsertUserRow) -> User {
  User(
    id: row.id,
    email: row.email,
    username: row.username,
    created_at: row.created_at,
    updated_at: row.updated_at,
  )
}
