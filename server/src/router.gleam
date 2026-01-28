import argus
import formal/form.{type Form}
import gleam/crypto
import gleam/json.{type Json}
import gleam/list
import gleam/result
import gleam/time/timestamp.{type Timestamp}
import pog
import shared
import sql
import web.{type Context}
import wisp.{type Request, type Response}

pub fn handle_request(request: Request, ctx: Context) -> Response {
  use request <- web.middleware(request)
  case wisp.path_segments(request) {
    ["api", "signup"] -> signup(request, ctx)
    _ -> wisp.not_found()
  }
  // let body = "<h1>hi from server</h1>"
  // wisp.html_response(body, 200)
}

type SignupError {
  // HashFailure(argus.HashError)
  InvalidQuery(pog.QueryError)
  UnexpectedQueryResult
  InvalidForm(Form(shared.Signup))
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
      //     signup.name,
      //     hashes.encoded_hash,
      //   )
      //   |> result.map_error(InvalidQuery),
      // )
      use returned <- result.try(
        sql.insert_user(
          ctx.conn,
          signup.email,
          signup.name,
          // TEMPORARY until jargon adds windows support
          signup.password,
        )
        |> result.map_error(InvalidQuery),
      )

      use insert_user_row <- result.try(
        list.first(returned.rows) |> result.replace_error(UnexpectedQueryResult),
      )
      let user = insert_user_row_to_user(insert_user_row)

      Ok(user)
    }
    Error(form) -> Error(InvalidForm(form))
  }

  case result {
    Ok(user) ->
      user |> user_to_json |> json.to_string |> wisp.json_response(201)
    Error(InvalidQuery(error)) -> internal_error()
    Error(UnexpectedQueryResult) -> internal_error()
    Error(InvalidForm(form)) -> invalid_form("Some fields are invalid")
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

fn user_to_json(user: shared.User) -> Json {
  let shared.User(id:, email:, name:, password_hash:, created_at:, updated_at:) =
    user
  json.object([
    #("id", json.int(id)),
    #("email", json.string(email)),
    #("name", json.string(name)),
    #("password_hash", json.string(password_hash)),
    #("created_at", timestamp_to_json(created_at)),
    #("updated_at", timestamp_to_json(updated_at)),
  ])
}

fn timestamp_to_json(timestamp: Timestamp) -> Json {
  timestamp |> timestamp.to_unix_seconds |> json.float
}

fn signup_form() -> Form(shared.Signup) {
  form.new({
    use email <- form.field("email", form.parse_email)
    use name <- form.field("name", form.parse_string |> form.check_not_empty)
    use password <- form.field(
      "password",
      form.parse_string
        |> form.check_not_empty
        |> form.check_string_length_more_than(8),
    )

    form.success(shared.Signup(email:, name:, password:))
  })
}

fn insert_user_row_to_user(row: sql.InsertUserRow) -> shared.User {
  shared.User(
    id: row.id,
    email: row.email,
    name: row.name,
    password_hash: row.password_hash,
    created_at: row.created_at,
    updated_at: row.updated_at,
  )
}
