import formal/form.{type Form}
import gleam/int
import gleam/list
import gleam/result
import gleam/string
import pog

pub type Error(f) {
  // HashFailure(argus.HashError)
  InvalidQuery(pog.QueryError)
  UnexpectedQueryResult
  InvalidForm(Form(f))
  InvalidSession(reason: String)
  InvalidCredentials
}

pub fn to_string(error: Error(f)) -> String {
  case error {
    InvalidQuery(error) ->
      case error {
        pog.ConstraintViolated(message:, constraint:, detail:) -> {
          "constraint violated. message: "
          <> message
          <> ", constraint: "
          <> constraint
          <> ", detail: "
          <> detail
        }
        pog.PostgresqlError(code:, name:, message:) -> {
          let code_name =
            pog.error_code_name(code) |> result.unwrap("mysterious_failure!")

          "query failed within the db. code name: "
          <> code_name
          <> ", name: "
          <> name
          <> ", message: "
          <> message
        }
        pog.UnexpectedArgumentCount(expected:, got:) -> {
          "unexpected argument count. expected: "
          <> int.to_string(expected)
          <> ", got: "
          <> int.to_string(got)
        }
        pog.UnexpectedArgumentType(expected:, got:) -> {
          "unexpected argument type. expected: " <> expected <> ", got: " <> got
        }
        pog.UnexpectedResultType(errors) ->
          errors
          |> list.map(fn(error) {
            "expected: " <> error.expected <> ", found: " <> error.found
          })
          |> string.join(", ")
        pog.QueryTimeout -> "query timed out"
        pog.ConnectionUnavailable -> "connection unavailable"
      }
    UnexpectedQueryResult -> "unexpected query result"
    InvalidForm(_) -> "invalid form"
    InvalidSession(reason:) -> "invalid session. reason: " <> reason
    InvalidCredentials ->
      "invalid credentials. username or password was incorrect"
  }
}
