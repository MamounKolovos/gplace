import birdie
import client
import client/data/user.{User}
import client/route
import client/route/signup
import gleeunit
import lustre/dev/query
import lustre/dev/simulate
import lustre/element

pub fn main() -> Nil {
  gleeunit.main()
}

pub fn user_signup_test() {
  let form = query.element(query.test_id("signup-form"))

  let app =
    simulate.application(client.init, client.update, client.view)
    |> simulate.start(Nil)
    |> simulate.message(client.UserNavigatedTo(route: route.Signup))
    // does nothing right now, add network.simulate later
    |> simulate.submit(
      on: form,
      fields: signup.FormInput(
        email: "example@gmail.com",
        username: "example",
        password: "password123",
      )
        |> signup.input_to_query,
    )

  //TODO: uncommon when i add loading state
  // let assert Ok(_) =
  //   query.find(
  //     in: simulate.view(app),
  //     matching: query.element(matching: query.text("skibidi")),
  //   )
  //   as "Should show loading state while logging in"

  let response = Ok(User(id: 0, username: "example"))

  app
  |> simulate.message(client.SignupMsg(signup.ApiReturnedUser(response)))
  |> simulate.message(client.UserNavigatedTo(route: route.Profile))
  |> simulate.view
  |> element.to_readable_string
  |> birdie.snap("Profile after signup")
}
