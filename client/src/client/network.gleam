import gleam/dynamic/decode
import gleam/json
import rsvp
import shared/api_error.{type ApiError}

pub type Error {
  ApiFailure(ApiError)
  InvalidApiResponse(String)
  TransportFailure(rsvp.Error)
}

pub fn expect_json(
  decoder: decode.Decoder(a),
  handler: fn(Result(a, Error)) -> msg,
) -> rsvp.Handler(msg) {
  use res <- rsvp.expect_json(decoder)

  let response = case res {
    Ok(data) -> Ok(data)
    Error(rsvp.HttpError(response)) ->
      case json.parse(response.body, api_error.decoder()) {
        Ok(api_error) -> Error(ApiFailure(api_error))
        Error(_decode_error) -> Error(InvalidApiResponse(response.body))
      }
    Error(error) -> Error(TransportFailure(error))
  }

  handler(response)
}
