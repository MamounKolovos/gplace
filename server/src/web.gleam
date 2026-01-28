import pog
import wisp

pub type Context {
  Context(db: pog.Connection)
}

pub fn middleware(
  request: wisp.Request,
  handle_request: fn(wisp.Request) -> wisp.Response,
) -> wisp.Response {
  let request = wisp.method_override(request)

  use <- wisp.log_request(request)
  // 500 response if request handler crashes
  use <- wisp.rescue_crashes()
  // converts head requests into get requests and returns an empty body
  use request <- wisp.handle_head(request)
  use request <- wisp.csrf_known_header_protection(request)
  handle_request(request)
}
