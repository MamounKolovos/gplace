import formal/form.{type Form}
import gleam/dynamic/decode
import gleam/float
import gleam/http
import gleam/http/request
import gleam/http/response
import gleam/int
import gleam/json.{type Json}
import gleam/list
import gleam/option.{type Option, None, Some}
import gleam/result
import gleam/string
import gleam/time/timestamp.{type Timestamp}
import gleam/uri.{type Uri}
import lustre
import lustre/attribute
import lustre/effect.{type Effect}
import lustre/element.{type Element}
import lustre/element/html
import lustre/event
import modem
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

/// Parsed form input
type AuthInput {
  SignupInput(email: String, username: String, password: String)
  LoginInput(username: String, password: String)
}

type User {
  User(id: Int, username: String)
}

type Model {
  Model(route: Route, page: Page)
}

type Page {
  AuthPage(form: Form(AuthInput), error_text: Option(String))
  ProfilePage(data: Option(User))
}

type Route {
  Auth(AuthRoute)
  Profile
}

type AuthRoute {
  Signup
  Login
}

type Shared {
  Shared
}

fn init(_args) -> #(Model, Effect(Msg)) {
  let route =
    modem.initial_uri()
    |> result.map(fn(uri) { uri.path_segments(uri.path) })
    |> fn(path) {
      case path {
        Ok(["signup"]) -> Auth(Signup)
        Ok(["login"]) -> Auth(Login)
        Ok(["profile"]) -> Profile
        _ -> Auth(Signup)
      }
    }

  case route {
    Auth(Signup) -> #(
      Model(route:, page: AuthPage(form: signup_form(), error_text: None)),
      modem.init(on_url_change),
    )
    Auth(Login) -> #(
      Model(route:, page: AuthPage(form: login_form(), error_text: None)),
      modem.init(on_url_change),
    )
    Profile -> #(
      Model(route:, page: ProfilePage(None)),
      effect.batch([
        modem.init(on_url_change),
        get_profile(),
      ]),
    )
  }
  // #(
  //   Model(route:, page: AuthPage(form: signup_form())),
  //   effect.batch([
  //     modem.replace("/signup", None, None),
  //     modem.init(on_url_change),
  //   ]),
  // )
}

fn on_url_change(uri: Uri) -> Msg {
  case uri.path_segments(uri.path) {
    ["signup"] -> OnRouteChange(Auth(Signup))
    ["login"] -> OnRouteChange(Auth(Login))
    ["profile"] -> OnRouteChange(Profile)
    _ -> OnRouteChange(Auth(Signup))
  }
}

fn login_form() -> Form(AuthInput) {
  form.new({
    use username <- form.field(
      "username",
      form.parse_string |> form.check_not_empty,
    )
    use password <- form.field(
      "password",
      form.parse_string
        |> form.check_not_empty
        |> form.check_string_length_more_than(8),
    )

    form.success(LoginInput(username:, password:))
  })
}

fn signup_form() -> Form(AuthInput) {
  form.new({
    use email <- form.field("email", form.parse_email)
    use username <- form.field(
      "username",
      form.parse_string |> form.check_not_empty,
    )
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

    form.success(SignupInput(email:, username:, password:))
  })
}

type Msg {
  OnRouteChange(Route)
  UserSubmittedAuthInput(Result(AuthInput, Form(AuthInput)))
  ApiReturnedUser(Result(User, Error))
}

fn update(model: Model, msg: Msg) -> #(Model, Effect(Msg)) {
  case msg {
    OnRouteChange(route) ->
      case route {
        Auth(Signup) -> #(
          Model(route:, page: AuthPage(form: signup_form(), error_text: None)),
          effect.none(),
        )
        Auth(Login) -> #(
          Model(route:, page: AuthPage(form: login_form(), error_text: None)),
          effect.none(),
        )
        _ -> #(Model(..model, route:), effect.none())
      }
    UserSubmittedAuthInput(result) ->
      case result {
        // add signupsubmitting model variant to disable buttons
        Ok(input) -> #(model, submit_auth(input))
        Error(form) -> #(
          Model(..model, page: AuthPage(form:, error_text: None)),
          effect.none(),
        )
      }
    ApiReturnedUser(result) ->
      case result {
        Ok(user) -> {
          #(
            Model(route: Profile, page: ProfilePage(Some(user))),
            modem.replace("/profile", None, None),
          )
        }
        Error(ApiFailure(shared.ApiError(code: _, message:))) ->
          case model.route {
            Auth(Signup) -> #(
              Model(
                route: Auth(Signup),
                page: AuthPage(form: signup_form(), error_text: Some(message)),
              ),
              effect.none(),
            )
            Auth(Login) -> #(
              Model(
                route: Auth(Login),
                page: AuthPage(form: login_form(), error_text: Some(message)),
              ),
              effect.none(),
            )
            Profile -> #(
              Model(
                route: Auth(Login),
                page: AuthPage(form: login_form(), error_text: Some(message)),
              ),
              effect.none(),
            )
          }
        // add error to model to render
        Error(_) -> #(model, effect.none())
      }
  }
}

fn get_profile() -> Effect(Msg) {
  let handler = expect_json(user_decoder(), ApiReturnedUser)
  rsvp.get("/api/me", handler)
}

fn submit_auth(input: AuthInput) -> Effect(Msg) {
  let #(path, body) = case input {
    SignupInput(email:, username:, password:) -> #("/api/signup", [
      #("email", email),
      #("username", username),
      #("password", password),
    ])

    LoginInput(username:, password:) -> #("/api/login", [
      #("username", username),
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

fn user_decoder() -> decode.Decoder(User) {
  use id <- decode.field("id", decode.int)
  use username <- decode.field("username", decode.string)
  decode.success(User(id:, username:))
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
    "INVALID_FORM" -> decode.success(shared.InvalidForm)
    "INTERNAL_ERROR" -> decode.success(shared.InternalError)
    "UNAUTHORIZED" -> decode.success(shared.Unauthorized)
    "INVALID_CREDENTIALS" -> decode.success(shared.InvalidCredentials)
    "DUPLICATE_IDENTIFIER" -> decode.success(shared.DuplicateIdentifier)
    _ -> decode.failure(shared.InternalError, "ApiErrorCode")
  }
}

fn view(model: Model) -> Element(Msg) {
  case model.route, model.page {
    Auth(route), AuthPage(form:, error_text:) ->
      auth_page_view(route, form, error_text)
    Profile, ProfilePage(data:) -> profile_page_view(data)
    _, _ -> {
      echo model
      html.text("not found :9")
    }
  }
}

fn profile_page_view(user: Option(User)) -> Element(Msg) {
  html.button([], [element.text("Profile")])
}

fn auth_page_view(
  route: AuthRoute,
  form: Form(AuthInput),
  error_text: Option(String),
) -> Element(Msg) {
  let fields = case route {
    Signup -> [
      form_input_field(form, name: "email", type_: "email", label: "Email"),
      form_input_field(form, name: "username", type_: "text", label: "Username"),
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
      form_input_field(form, name: "username", type_: "text", label: "Username"),
      form_input_field(
        form,
        name: "password",
        type_: "password",
        label: "Password",
      ),
    ]
  }

  html.div([], [
    auth_mode_toggle(route),
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
        case error_text {
          Some(error_text) -> auth_page_error_box(error_text)
          None -> element.none()
        },
        html.div([], [
          html.input([
            attribute.type_("submit"),
            attribute.value(case route {
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

fn auth_page_error_box(error_text: String) -> Element(Msg) {
  html.div(
    [
      attribute.role("alert"),
      attribute.class(
        "bg-red-100 border border-red-400 text-red-700 px-4 py-3 rounded relative",
      ),
    ],
    [
      html.strong([attribute.class("font-bold")], [element.text("Error!")]),
      html.span([attribute.class("block sm:inline ml-2")], [
        element.text(error_text),
      ]),
    ],
  )
}

fn auth_mode_toggle(route: AuthRoute) -> Element(Msg) {
  // flex lays out the buttons horizontally
  html.div([attribute.styles([#("display", "flex"), #("gap", "0.5rem")])], [
    html.a(
      [
        attribute.href("/signup"),
        attribute.styles([
          // forces buttons to take equal width regardless of text
          #("flex", "1"),
          #("padding", "0.5rem"),
          #("border-radius", "0.5rem"),
          #("text-align", "center"),
          #("font-weight", case route {
            Signup -> "600"
            Login -> "400"
          }),
          #("background-color", case route {
            Signup -> "#ffffff"
            Login -> "#f3f4f6"
          }),
          #("color", case route {
            Signup -> "#000000"
            Login -> "#9ca3af"
          }),
          #("cursor", "pointer"),
          #("border", "1px solid #d1d5db"),
        ]),
      ],
      [element.text("Sign up")],
    ),
    html.a(
      [
        attribute.href("/login"),
        attribute.styles([
          #("flex", "1"),
          #("padding", "0.5rem"),
          #("border-radius", "0.5rem"),
          #("text-align", "center"),
          #("font-weight", case route {
            Login -> "600"
            Signup -> "400"
          }),
          #("background-color", case route {
            Login -> "#ffffff"
            Signup -> "#f3f4f6"
          }),
          #("color", case route {
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
