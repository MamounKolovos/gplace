import client/data/user.{type User}
import client/network
import client/session.{type Session}
import gleam/int
import gleam/option.{type Option, None, Some}
import gleam/time/timestamp.{type Timestamp}
import lustre/effect.{type Effect}
import lustre/element.{type Element}
import rsvp
import shared/user_stats.{type UserStats}

pub type Model {
  Model(stats: Option(Stats))
}

pub type Stats {
  Stats(tiles_placed: Int, last_placed_at: Option(Timestamp))
}

pub type Msg {
  ApiReturnedUser(Result(User, network.Error))
  ApiReturnedUserStats(Result(UserStats, network.Error))
}

pub fn init() -> #(Model, Effect(Msg)) {
  #(Model(stats: None), fetch_stats())
}

pub fn update(
  session: Session,
  model: Model,
  msg: Msg,
) -> #(Session, Model, Effect(Msg)) {
  case msg {
    ApiReturnedUserStats(result) ->
      case result {
        Ok(user_stats) -> {
          let stats =
            Some(Stats(
              tiles_placed: user_stats.tiles_placed,
              last_placed_at: user_stats.last_placed_at,
            ))
          let model = Model(stats:)
          #(session, model, effect.none())
        }
        Error(_) -> #(session, model, effect.none())
      }
    _ -> #(session, model, effect.none())
  }
}

fn fetch_stats() -> Effect(Msg) {
  let handler = network.expect_json(user_stats.decoder(), ApiReturnedUserStats)
  rsvp.get("/api/stats", handler)
}

pub fn view(session: Session, model: Model) -> Element(Msg) {
  case session {
    session.Unknown -> element.text("trying to authenticate, please wait")
    session.Pending(on_success: _, on_error: _) ->
      element.text("trying to authenticate, please wait")
    session.LoggedOut -> element.text("please login to view this page")
    session.LoggedIn(user:) -> {
      case model.stats {
        Some(stats) -> element.text(int.to_string(stats.tiles_placed))
        None -> element.text("username: " <> user.username)
      }
    }
  }
}
