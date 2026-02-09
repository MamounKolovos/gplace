pub type ApiErrorCode {
  InvalidForm
  InternalError
  Unauthorized
  InvalidCredentials
  DuplicateIdentifier
}

pub type ApiError {
  ApiError(code: ApiErrorCode, message: String)
}
