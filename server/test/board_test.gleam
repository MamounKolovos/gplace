import fixture
import server/board

pub fn persist_and_rehydrate_test() {
  use conn, user, _ <- fixture.with_user

  let board = board.init(conn, width: 50, height: 50)
  assert board.get_tile(board, x: 3, y: 3) == Ok(0)

  let assert Ok(_) = board.set_tile(board, user, x: 3, y: 3, color: 5)

  let board = board.init(conn, width: 50, height: 50)
  assert board.get_tile(board, x: 3, y: 3) == Ok(5)
}
