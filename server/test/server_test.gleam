import gleam/http
import gleam/http/request
import gleam/json
import gleam/uri
import gleeunit
import global_value
import pog
import router
import server
import sql
import web.{type Context, Context}
import wisp/simulate

pub fn main() -> Nil {
  gleeunit.main()
}

fn global_connection_pool() -> pog.Connection {
  global_value.create_with_unique_name(
    "server_test.global_connection_pool",
    fn() { server.new_conn() },
  )
}

fn with_connection(test_case: fn(pog.Connection) -> a) -> Nil {
  let pool = global_connection_pool()
  let assert Error(pog.TransactionRolledBack(Nil)) =
    pog.transaction(pool, fn(conn) {
      test_case(conn)
      Error(Nil)
    })
  Nil
}

fn with_context(test_case: fn(Context) -> a) -> Nil {
  use conn <- with_connection()
  let ctx = Context(conn)
  test_case(ctx)
  Nil
}

pub fn insert_user_test() {
  use conn <- with_connection()

  let assert Ok(returned) =
    sql.insert_user(conn, "example@gmail.com", "example", "password123")
  let assert [insert_user_row] = returned.rows
  let assert sql.InsertUserRow(
    id: _,
    email: "example@gmail.com",
    username: "example",
    created_at: _,
    updated_at: _,
  ) = insert_user_row
}
// pub fn signup_user_test() {
//   let body = [
//     #("email", "example@gmail.com"),
//     #("username", "example"),
//     #("password", "password123"),
//   ]
//   let request =
//     simulate.request(http.Post, "/api/signup")
//     |> simulate.form_body(body)

//   use ctx <- with_context()
//   let response = router.handle_request(request, ctx)
//   let body = simulate.read_body(response)
//   todo
// }
