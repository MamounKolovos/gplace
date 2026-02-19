import client/data/user.{type User}
import client/network
import client/route.{type Route}
import client/route/login
import client/route/play
import client/route/profile
import client/route/signup
import client/session.{type Session}
import gleam/bool
import lustre
import lustre/effect.{type Effect}
import lustre/element.{type Element}
import lustre/element/html
import modem
import rsvp
import shared/api_error.{ApiError}

pub fn main() -> Nil {
  let app = lustre.application(init, update, view)
  let assert Ok(_) = lustre.start(app, "#app", Nil)
  Nil
}

type Model {
  Model(session: Session, route: Route, page: Page)
}

type Page {
  Signup(signup.Model)
  Login(login.Model)
  Profile(profile.Model)
  Play(play.Model)
}

type Msg {
  UserNavigatedTo(route: Route)
  SignupMsg(signup.Msg)
  LoginMsg(login.Msg)
  ProfileMsg(profile.Msg)
  PlayMsg(play.Msg)
  SessionValidated(Result(User, network.Error))
}

fn init(_args) -> #(Model, Effect(Msg)) {
  let route = route.initial_route()
  let is_protected = route.is_protected(route)

  let configure_router =
    modem.init(fn(uri) { uri |> route.parse |> UserNavigatedTo })
  let get_user = user.get(SessionValidated)

  let session = case route {
    route.Signup | route.Login ->
      session.Pending(on_success: route.Profile, on_error: route)
    route if is_protected ->
      session.Pending(on_success: route, on_error: route.Login)
    _ -> session.Unknown
  }

  let #(page, page_effect) = load_route(route)
  let effect = effect.batch([configure_router, get_user, page_effect])
  #(Model(session:, route:, page:), effect)
}

fn load_route(route: Route) -> #(Page, Effect(Msg)) {
  case route {
    route.Signup -> {
      let #(page_model, page_effect) = signup.init()

      #(Signup(page_model), page_effect |> effect.map(SignupMsg))
    }
    route.Login -> {
      let #(page_model, page_effect) = login.init()

      #(Login(page_model), page_effect |> effect.map(LoginMsg))
    }
    route.Profile -> {
      let #(page_model, page_effect) = profile.init()

      #(Profile(page_model), page_effect |> effect.map(ProfileMsg))
    }
    route.Play -> {
      let #(page_model, page_effect) = play.init()

      #(Play(page_model), page_effect |> effect.map(PlayMsg))
    }
    route.NotFound(uri:) -> todo
  }
}

fn update(model: Model, msg: Msg) -> #(Model, Effect(Msg)) {
  case model, msg {
    model, UserNavigatedTo(route) -> {
      use <- bool.guard(model.route == route, return: #(model, effect.none()))

      let is_protected = route.is_protected(route)
      let route = case model.session, route {
        session.LoggedOut, _ if is_protected -> route.Login
        session.LoggedIn(_), route.Signup | session.LoggedIn(_), route.Login ->
          route.Profile
        _, route -> route
      }

      let #(page, page_effect) = load_route(route)

      #(Model(..model, route:, page:), page_effect)
    }
    Model(session:, route: route.Signup, page: Signup(page_model)),
      SignupMsg(msg)
    -> {
      let #(session, page_model, effect) =
        signup.update(session, page_model, msg)

      #(
        Model(..model, session:, page: Signup(page_model)),
        effect |> effect.map(SignupMsg),
      )
    }
    Model(session:, route: route.Login, page: Login(page_model)), LoginMsg(msg) -> {
      let #(session, page_model, effect) =
        login.update(session, page_model, msg)

      #(
        Model(..model, session:, page: Login(page_model)),
        effect |> effect.map(LoginMsg),
      )
    }
    Model(session:, route: route.Profile, page: Profile(page_model)),
      ProfileMsg(msg)
    -> {
      let #(session, page_model, effect) =
        profile.update(session, page_model, msg)

      #(
        Model(..model, session:, page: Profile(page_model)),
        effect |> effect.map(ProfileMsg),
      )
    }
    Model(session:, route: route.Play, page: Play(page_model)), PlayMsg(msg) -> {
      let #(session, page_model, effect) = play.update(session, page_model, msg)

      #(
        Model(..model, session:, page: Play(page_model)),
        effect |> effect.map(PlayMsg),
      )
    }
    Model(session: session.Pending(on_success:, on_error:), route: _, page: _),
      SessionValidated(result)
    ->
      case result {
        Ok(user) -> #(
          Model(..model, session: session.login(user)),
          route.push(on_success),
        )
        Error(_) -> #(
          Model(..model, session: session.logout()),
          route.push(on_error),
        )
      }

    // guests don't need to be re-routed, just get their session updated passively
    Model(session: session.Unknown, route: _, page: _), SessionValidated(result)
    ->
      case result {
        Ok(user) -> #(
          Model(..model, session: session.login(user)),
          effect.none(),
        )
        Error(_) -> #(Model(..model, session: session.logout()), effect.none())
      }
    model, _ -> #(model, effect.none())
  }
}

fn view(model: Model) -> Element(Msg) {
  case model {
    Model(session: _, route: route.Signup, page: Signup(model)) ->
      signup.view(model) |> element.map(SignupMsg)
    Model(session: _, route: route.Login, page: Login(model)) ->
      login.view(model) |> element.map(LoginMsg)
    Model(session:, route: route.Profile, page: Profile(model)) ->
      profile.view(session, model) |> element.map(ProfileMsg)
    Model(session: _, route: route.Play, page: Play(model)) ->
      play.view(model) |> element.map(PlayMsg)
    _ -> html.text("not found")
  }
}
