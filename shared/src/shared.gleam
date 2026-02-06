pub type ApiErrorCode {
  InvalidFormCode
  InternalError
  Unauthorized
  InvalidCredentials
}

pub type ApiError {
  ApiError(code: ApiErrorCode, message: String)
}
