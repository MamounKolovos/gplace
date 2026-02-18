import gleam/dynamic/decode

pub type Code {
  InvalidForm
  InternalError
  Unauthenticated
  InvalidCredentials
  DuplicateIdentifier
}

pub type ApiError {
  ApiError(code: Code, message: String)
}

pub fn decoder() -> decode.Decoder(ApiError) {
  decode.at(["error"], {
    use code <- decode.field("code", api_error_code_decoder())
    use message <- decode.field("message", decode.string)
    decode.success(ApiError(code:, message:))
  })
}

fn api_error_code_decoder() -> decode.Decoder(Code) {
  use variant <- decode.then(decode.string)
  case variant {
    "INVALID_FORM" -> decode.success(InvalidForm)
    "INTERNAL_ERROR" -> decode.success(InternalError)
    "UNAUTHENTICATED" -> decode.success(Unauthenticated)
    "INVALID_CREDENTIALS" -> decode.success(InvalidCredentials)
    "DUPLICATE_IDENTIFIER" -> decode.success(DuplicateIdentifier)
    _ -> decode.failure(InternalError, "Code")
  }
}
