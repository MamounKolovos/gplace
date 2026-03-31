import fixture
import gleam/time/timestamp
import server/board
import server/user

pub fn persist_and_rehydrate_test() {
  use conn, user, _ <- fixture.with_user

  let board = board.init(conn, width: 50, height: 50)
  assert board.get_tile(board, x: 3, y: 3) == Ok(0)

  let assert Ok(_) =
    board.set_tile(
      board,
      user,
      x: 3,
      y: 3,
      color: 5,
      now: timestamp.system_time(),
    )

  let board = board.init(conn, width: 50, height: 50)
  assert board.get_tile(board, x: 3, y: 3) == Ok(5)
}

pub fn tiles_placed_increment_test() {
  use conn, user, _ <- fixture.with_user

  let board = board.init(conn, width: 50, height: 50)

  let assert Ok(user.Stats(tiles_placed: 0, ..)) = user.get_stats(user, conn)

  let assert Ok(_) =
    board.set_tile(
      board,
      user,
      x: 0,
      y: 0,
      color: 5,
      now: timestamp.system_time(),
    )

  let assert Ok(user.Stats(tiles_placed: 1, ..)) = user.get_stats(user, conn)
}
