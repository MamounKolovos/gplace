import client/network
import client/router
import client/session.{type Session}
import client/user.{type User}
import formal/form.{type Form}
import gleam/http
import gleam/http/request
import gleam/option.{type Option, None, Some}
import gleam/string
import gleam/uri
import lustre/attribute
import lustre/effect.{type Effect}
import lustre/element.{type Element}
import lustre/element/html
import lustre/event
import rsvp
import shared/api_error.{ApiError}

pub type Model {
  Model(form: Form(FormInput), error_text: Option(String))
}

pub type Msg {
  UserSubmittedFormInput(Result(FormInput, Form(FormInput)))
  ApiReturnedUser(Result(User, network.Error))
}

pub type FormInput {
  FormInput(email: String, username: String, password: String)
}

pub fn init() -> #(Model, Effect(Msg)) {
  #(Model(form: signup_form(), error_text: None), reset_form("signup-form"))
}

fn reset_form(id: String) -> Effect(Msg) {
  use _, _ <- effect.after_paint()
  do_reset_form(id)
}

@external(javascript, "../client_ffi.mjs", "resetForm")
fn do_reset_form(id: String) -> Nil

fn signup_form() -> Form(FormInput) {
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

    form.success(FormInput(email:, username:, password:))
  })
}

pub fn update(
  session: Session,
  model: Model,
  msg: Msg,
) -> #(Session, Model, Effect(Msg)) {
  case msg {
    UserSubmittedFormInput(result) ->
      case result {
        Ok(input) -> #(session, model, submit_form(input))
        Error(form) -> #(session, Model(form:, error_text: None), effect.none())
      }
    ApiReturnedUser(result) ->
      case result {
        Ok(user) -> #(session.login(user), model, router.push(router.Profile))
        Error(network.ApiFailure(ApiError(code: _, message:))) -> #(
          session,
          Model(..model, error_text: Some(message)),
          effect.none(),
        )
        Error(_) -> #(
          session,
          Model(
            ..model,
            error_text: Some("Invalid api response or transport failure"),
          ),
          effect.none(),
        )
      }
  }
}

fn submit_form(input: FormInput) -> Effect(Msg) {
  let path = "/api/signup"
  let assert Ok(uri) = rsvp.parse_relative_uri(path)
  let assert Ok(request) = request.from_uri(uri)
  let handler = network.expect_json(user.decoder(), ApiReturnedUser)

  request
  |> request.set_method(http.Post)
  |> request.set_header("content-type", "application/x-www-form-urlencoded")
  |> request.set_body(input |> input_to_query |> uri.query_to_string)
  |> rsvp.send(handler)
}

pub fn input_to_query(input: FormInput) -> List(#(String, String)) {
  [
    #("email", input.email),
    #("username", input.username),
    #("password", input.password),
  ]
}

pub fn view(model: Model) -> Element(Msg) {
  html.div(
    [
      // centers card
      attribute.class(
        "min-h-screen flex justify-center items-start bg-gray-50 p-10",
      ),
    ],
    [signup_view(model)],
  )
}

fn signup_view(model: Model) -> Element(Msg) {
  let fields = [
    form_input_field_view(
      model.form,
      name: "email",
      type_: "email",
      label: "Email",
    ),
    form_input_field_view(
      model.form,
      name: "username",
      type_: "text",
      label: "Username",
    ),
    form_input_field_view(
      model.form,
      name: "password",
      type_: "password",
      label: "Password",
    ),
    form_input_field_view(
      model.form,
      name: "confirm_password",
      type_: "password",
      label: "Confirmation",
    ),
  ]

  html.div(
    [
      attribute.class(
        "w-full max-w-md bg-white rounded-lg shadow p-6 flex flex-col gap-6",
      ),
    ],
    [
      auth_toggle_view(),
      html.form(
        [
          attribute.id("signup-form"),
          // prevents default submission and collects field values
          event.on_submit(fn(fields) {
            model.form
            |> form.add_values(fields)
            |> form.run
            |> UserSubmittedFormInput
          }),
        ],
        [
          element.fragment(fields),
          case model.error_text {
            Some(error_text) -> error_box_view(error_text)
            None -> element.none()
          },
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
      ),
    ],
  )
}

fn error_box_view(error_text: String) -> Element(Msg) {
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

fn auth_toggle_view() -> Element(Msg) {
  // flex lays out the buttons horizontally
  html.div([attribute.styles([#("display", "flex"), #("gap", "0.5rem")])], [
    html.a(
      [
        attribute.styles([
          // forces buttons to take equal width regardless of text
          #("flex", "1"),
          #("padding", "0.5rem"),
          #("border-radius", "0.5rem"),
          #("text-align", "center"),
          #("font-weight", "600"),
          #("background-color", "#ffffff"),
          #("color", "#000000"),
          #("cursor", "pointer"),
          #("border", "1px solid #d1d5db"),
        ]),
      ],
      [element.text("Sign up")],
    ),
    html.a(
      [
        router.href(router.Login),
        attribute.styles([
          #("flex", "1"),
          #("padding", "0.5rem"),
          #("border-radius", "0.5rem"),
          #("text-align", "center"),
          #("font-weight", "400"),
          #("background-color", "#f3f4f6"),
          #("color", "#9ca3af"),
          #("cursor", "pointer"),
          #("border", "1px solid #d1d5db"),
        ]),
      ],
      [element.text("Log in")],
    ),
  ])
}

fn form_input_field_view(
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
