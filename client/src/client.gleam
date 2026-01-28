import formal/form.{type Form}
import gleam/dynamic/decode
import gleam/float
import gleam/http
import gleam/http/request
import gleam/http/response
import gleam/json.{type Json}
import gleam/list
import gleam/result
import gleam/time/timestamp.{type Timestamp}
import gleam/uri
import lustre
import lustre/attribute
import lustre/effect.{type Effect}
import lustre/element.{type Element}
import lustre/element/html
import lustre/event
import rsvp
import shared

pub fn main() -> Nil {
  let app = lustre.application(init, update, view)
  let assert Ok(_) = lustre.start(app, "#app", Nil)
  Nil
}

//TODO: add error_to_string
type Error {
  /// The api call failed with some domain-specific error
  ApiFailure(shared.ApiError)
  InvalidApiResponse(String)
  /// There was a network problem or something else went wrong with the request itself
  TransportFailure(rsvp.Error)
}

type Model {
  SignupPage(form: Form(shared.Signup))
  MainPage(data: shared.User)
}

fn init(_args) -> #(Model, Effect(Msg)) {
  #(SignupPage(signup_form()), effect.none())
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

    use _ <- form.field(
      "confirm_password",
      form.parse_string |> form.check_confirms(password),
    )

    form.success(shared.Signup(email:, name:, password:))
  })
}

type Msg {
  UserClickedSignupButton(Result(shared.Signup, Form(shared.Signup)))
  ApiReturnedUser(Result(shared.User, Error))
}

fn update(model: Model, msg: Msg) -> #(Model, Effect(Msg)) {
  case msg {
    UserClickedSignupButton(result) ->
      case result {
        //add signupsubmitting model variant to disable buttons
        Ok(signup) -> #(model, post_signup(signup))
        Error(form) -> #(SignupPage(form), effect.none())
      }
    ApiReturnedUser(result) ->
      case result {
        Ok(user) -> #(MainPage(user), effect.none())
        // add error to model to render
        Error(_) -> #(model, effect.none())
      }
  }
}

fn post_signup(signup: shared.Signup) -> Effect(Msg) {
  let assert Ok(uri) = rsvp.parse_relative_uri("/api/signup")
  let assert Ok(request) = request.from_uri(uri)

  let body =
    uri.query_to_string([
      #("email", signup.email),
      #("name", signup.name),
      #("password", signup.password),
    ])

  let handler = expect_json(user_decoder(), ApiReturnedUser)

  request
  |> request.set_method(http.Post)
  |> request.set_header("content-type", "application/x-www-form-urlencoded")
  |> request.set_body(body)
  |> rsvp.send(handler)
}

fn expect_json(
  decoder: decode.Decoder(a),
  handler: fn(Result(a, Error)) -> msg,
) -> rsvp.Handler(msg) {
  use res <- rsvp.expect_json(decoder)

  let response = case res {
    Ok(data) -> Ok(data)
    Error(rsvp.HttpError(response)) ->
      case json.parse(response.body, api_error_decoder()) {
        Ok(api_error) -> Error(ApiFailure(api_error))
        Error(_decode_error) -> Error(InvalidApiResponse(response.body))
      }
    Error(error) -> Error(TransportFailure(error))
  }

  handler(response)
}

pub fn user_decoder() -> decode.Decoder(shared.User) {
  use id <- decode.field("id", decode.int)
  use email <- decode.field("email", decode.string)
  use name <- decode.field("name", decode.string)
  use created_at <- decode.field("created_at", timestamp_decoder())
  use updated_at <- decode.field("updated_at", timestamp_decoder())
  decode.success(shared.User(id:, email:, name:, created_at:, updated_at:))
}

fn timestamp_decoder() -> decode.Decoder(Timestamp) {
  use value <- decode.then(decode.float)
  value |> float.round |> timestamp.from_unix_seconds |> decode.success
}

fn api_error_decoder() -> decode.Decoder(shared.ApiError) {
  let decoder = {
    use code <- decode.field("code", api_error_code_decoder())
    use message <- decode.field("message", decode.string)
    decode.success(shared.ApiError(code:, message:))
  }
  decode.at(["error"], decoder)
}

fn api_error_code_decoder() -> decode.Decoder(shared.ApiErrorCode) {
  use variant <- decode.then(decode.string)
  case variant {
    "INVALID_FORM" -> decode.success(shared.InvalidFormCode)
    "INTERNAL_ERROR" -> decode.success(shared.InternalError)
    _ -> decode.failure(shared.InternalError, "ApiErrorCode")
  }
}

fn view(model: Model) -> Element(Msg) {
  case model {
    SignupPage(form) -> signup_page_view(form)
    MainPage(_) -> html.text("successful sign in!")
  }
}

fn signup_page_view(form: Form(shared.Signup)) -> Element(Msg) {
  html.form(
    [
      // prevents default submission and collects field values
      event.on_submit(fn(fields) {
        form |> form.add_values(fields) |> form.run |> UserClickedSignupButton
      }),
    ],
    [
      form_input_field(form, name: "email", type_: "email", label: "Email"),
      form_input_field(form, name: "name", type_: "text", label: "Name"),
      form_input_field(
        form,
        name: "password",
        type_: "password",
        label: "Password",
      ),
      form_input_field(
        form,
        name: "confirm_password",
        type_: "password",
        label: "Confirmation",
      ),
      html.div([], [
        html.input([
          attribute.type_("submit"),
          attribute.value("Sign up"),
          attribute.styles([
            #("margin-top", "1rem"),
            #("padding", "0.6rem 1rem"),
            #("background-color", "#2563eb"),
            #("color", "white"),
            #("font-weight", "600"),
            #("border", "none"),
            #("border-radius", "6px"),
            #("cursor", "pointer"),
            #("width", "100%"),
          ]),
        ]),
      ]),
    ],
  )
}

fn form_input_field(
  form: Form(f),
  name name: String,
  type_ type_: String,
  label label_text: String,
) -> Element(Msg) {
  let errors = form.field_error_messages(form, name)
  let styles =
    attribute.styles([#("display", "block"), #("margin-bottom", "0.75rem")])

  html.label([styles], [
    element.text(label_text),
    html.input([
      attribute.type_(type_),
      attribute.name(name),
      attribute.value(form.field_value(form, name)),
      attribute.styles([
        #("display", "block"),
        #("width", "100%"),
        #("padding", "0.5rem"),
        #("margin-top", "0.25rem"),
        #("border", "1px solid #ccc"),
        #("border-radius", "4px"),
      ]),
      ..{
        case errors {
          [] -> [attribute.none()]
          _ -> [
            attribute.aria_invalid("true"),
            attribute.style("border", "1px solid #dc2626"),
          ]
        }
      }
    ]),

    list.map(errors, fn(error) { html.small([], [element.text(error)]) })
      |> element.fragment,
  ])
}
