import gleam/time/timestamp.{type Timestamp}

pub type ApiErrorCode {
  InvalidFormCode
  InternalError
}

pub type ApiError {
  ApiError(code: ApiErrorCode, message: String)
}

pub type Signup {
  Signup(email: String, username: String, password: String)
}

pub type User {
  User(
    id: Int,
    email: String,
    username: String,
    created_at: Timestamp,
    updated_at: Timestamp,
  )
}
