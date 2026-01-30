import formal/form.{type Form}
import gleam/dynamic/decode
import gleam/float
import gleam/http
import gleam/http/request
import gleam/http/response
import gleam/json.{type Json}
import gleam/list
import gleam/result
import gleam/string
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

/// For model to show/hide form fields accordingly
type AuthMode {
  Signup
  Login
}

/// Parsed form input
type AuthInput {
  SignupInput(email: String, name: String, password: String)
  LoginInput(name: String, password: String)
}

type Model {
  AuthPage(mode: AuthMode, form: Form(AuthInput))
  MainPage(data: shared.User)
}

fn init(_args) -> #(Model, Effect(Msg)) {
  #(AuthPage(mode: Signup, form: signup_form()), effect.none())
}

fn login_form() -> Form(AuthInput) {
  form.new({
    use name <- form.field("name", form.parse_string |> form.check_not_empty)
    use password <- form.field(
      "password",
      form.parse_string
        |> form.check_not_empty
        |> form.check_string_length_more_than(8),
    )

    form.success(LoginInput(name:, password:))
  })
}

fn signup_form() -> Form(AuthInput) {
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

    form.success(SignupInput(email:, name:, password:))
  })
}

type Msg {
  UserToggledAuthMode(AuthMode)
  UserSubmittedAuthInput(Result(AuthInput, Form(AuthInput)))
  ApiReturnedUser(Result(shared.User, Error))
}

fn update(model: Model, msg: Msg) -> #(Model, Effect(Msg)) {
  case msg {
    UserToggledAuthMode(mode) ->
      case mode {
        Signup -> #(AuthPage(Signup, signup_form()), effect.none())
        Login -> #(AuthPage(Login, login_form()), effect.none())
      }
    UserSubmittedAuthInput(result) ->
      case result {
        // add signupsubmitting model variant to disable buttons
        Ok(input) -> #(model, submit_auth(input))
        Error(form) ->
          case model {
            AuthPage(mode:, form: _) -> #(AuthPage(mode:, form:), effect.none())
            model -> #(model, effect.none())
          }
      }
    ApiReturnedUser(result) ->
      case result {
        Ok(user) -> #(MainPage(user), effect.none())
        // add error to model to render
        Error(_) -> #(model, effect.none())
      }
  }
}

fn submit_auth(input: AuthInput) -> Effect(Msg) {
  let #(path, body) = case input {
    SignupInput(email, name, password) -> #("/api/signup", [
      #("email", email),
      #("name", name),
      #("password", password),
    ])

    LoginInput(name, password) -> #("/api/login", [
      #("name", name),
      #("password", password),
    ])
  }

  let assert Ok(uri) = rsvp.parse_relative_uri(path)
  let assert Ok(request) = request.from_uri(uri)
  let handler = expect_json(user_decoder(), ApiReturnedUser)

  request
  |> request.set_method(http.Post)
  |> request.set_header("content-type", "application/x-www-form-urlencoded")
  |> request.set_body(uri.query_to_string(body))
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
    AuthPage(mode:, form:) -> auth_page_view(mode, form)
    MainPage(_) -> html.text("successful sign in!")
  }
}

fn auth_page_view(mode: AuthMode, form: Form(AuthInput)) -> Element(Msg) {
  let fields = case mode {
    Signup -> [
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
    ]
    Login -> [
      form_input_field(form, name: "name", type_: "text", label: "Name"),
      form_input_field(
        form,
        name: "password",
        type_: "password",
        label: "Password",
      ),
    ]
  }

  html.div([], [
    auth_mode_toggle(mode),
    html.form(
      [
        // prevents default submission and collects field values
        event.on_submit(fn(fields) {
          form
          |> form.add_values(fields)
          |> form.run
          |> UserSubmittedAuthInput
        }),
      ],
      [
        element.fragment(fields),
        html.div([], [
          html.input([
            attribute.type_("submit"),
            attribute.value(case mode {
              Signup -> "Sign up"
              Login -> "Login"
            }),
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
    ),
  ])
}

fn auth_mode_toggle(mode: AuthMode) -> Element(Msg) {
  // flex lays out the buttons horizontally
  html.div([attribute.styles([#("display", "flex"), #("gap", "0.5rem")])], [
    html.button(
      [
        event.on_click(UserToggledAuthMode(Signup)),
        attribute.styles([
          // forces buttons to take equal width regardless of text
          #("flex", "1"),
          #("padding", "0.5rem"),
          #("border-radius", "0.5rem"),
          #("text-align", "center"),
          #("font-weight", case mode {
            Signup -> "600"
            Login -> "400"
          }),
          #("background-color", case mode {
            Signup -> "#ffffff"
            Login -> "#f3f4f6"
          }),
          #("color", case mode {
            Signup -> "#000000"
            Login -> "#9ca3af"
          }),
          #("cursor", "pointer"),
          #("border", "1px solid #d1d5db"),
        ]),
      ],
      [element.text("Sign up")],
    ),
    html.button(
      [
        event.on_click(UserToggledAuthMode(Login)),
        attribute.styles([
          #("flex", "1"),
          #("padding", "0.5rem"),
          #("border-radius", "0.5rem"),
          #("text-align", "center"),
          #("font-weight", case mode {
            Login -> "600"
            Signup -> "400"
          }),
          #("background-color", case mode {
            Login -> "#ffffff"
            Signup -> "#f3f4f6"
          }),
          #("color", case mode {
            Login -> "#000000"
            Signup -> "#9ca3af"
          }),
          #("cursor", "pointer"),
          #("border", "1px solid #d1d5db"),
        ]),
      ],
      [element.text("Log in")],
    ),
  ])
}

fn form_input_field(
  form: Form(f),
  name name: String,
  type_ type_: String,
  label label_text: String,
) -> Element(Msg) {
  let label_styles =
    attribute.styles([#("display", "block"), #("margin-bottom", "0.75rem")])

  let errors = form.field_error_messages(form, name)

  html.label([label_styles], [
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

    html.small([], [errors |> string.join(with: ", ") |> element.text]),
  ])
}
