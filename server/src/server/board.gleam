import gleam/bool
import gleam/erlang/process.{type Subject}
import gleam/list
import gleam/otp/actor
import gleam/otp/supervision
import gleam/result
import pog
import server/board_store
import server/database
import server/user.{type User}
import shared/snapshot.{type Snapshot, Snapshot}

pub opaque type Board {
  Board(
    store: board_store.BoardStore,
    db: pog.Connection,
    width: Int,
    height: Int,
  )
}

// pub opaque type Config {
//   Config(width: Int, height: Int, max_color: Int)
// }

// pub fn new(
//   width width: Int,
//   height height: Int,
//   max_color max_color: Int,
// ) -> Config {
//   Config(width:, height:, max_color:)
// }

pub fn supervised(
  name: process.Name(Message),
  db: pog.Connection,
  width: Int,
  height: Int,
) -> supervision.ChildSpecification(Nil) {
  supervision.worker(fn() {
    // TODO: make this dynamic based off of how large the board is
    actor.new_with_initialiser(5000, fn(_) {
      random(db, width:, height:)
      |> actor.initialised
      |> Ok
    })
    |> actor.on_message(handle_message)
    |> actor.named(name)
    |> actor.start
  })
}

pub type Message {
  Get(reply_with: Subject(Board))
}

fn handle_message(board: Board, message: Message) -> actor.Next(Board, Message) {
  case message {
    Get(reply_with:) -> {
      process.send(reply_with, board)
      actor.continue(board)
    }
  }
}

pub fn get(subject: Subject(Message)) -> Board {
  process.call(subject, 1000, Get)
}

// Will uncomment all writer code when it's time to stress test

pub fn init(db: pog.Connection, width width: Int, height height: Int) -> Board {
  // let assert Ok(actor) =
  //   actor.new_with_initialiser(1000, fn(subject) {
  //     process.send_after(subject, 5000, Flush)

  //     actor.initialised(WriterState(subject:, pending: deque.new(), db:))
  //     |> actor.returning(subject)
  //     |> Ok
  //   })
  //   |> actor.on_message(handle_message)
  //   |> actor.start

  // let writer = actor.data

  let assert Ok(_) =
    database.init_board(
      db,
      width: width,
      height: height,
      max_color: 15,
      initial_color: 0,
    )

  let assert Ok(rows) = database.select_board(db)
  let colors = list.map(rows, fn(row) { row.color })

  let store = board_store.hydrate(using: colors, width: width, height: height)

  Board(store:, db:, width:, height:)
}

pub fn random(db: pog.Connection, width width: Int, height height: Int) -> Board {
  let assert Ok(_) =
    database.init_random_board(db, width:, height:, max_color: 15)

  let assert Ok(rows) = database.select_board(db)
  let colors = list.map(rows, fn(row) { row.color })

  let store = board_store.hydrate(using: colors, width: width, height: height)

  Board(store:, db:, width:, height:)
}

// type WriterMessage {
//   Shutdown
//   Flush
//   SetTile(TileUpdate)
// }

// type TileUpdate {
//   TileUpdate(x: Int, y: Int, color: Int, user_id: Int)
// }

// type WriterState {
//   WriterState(
//     subject: Subject(WriterMessage),
//     pending: Deque(TileUpdate),
//     db: pog.Connection,
//   )
// }

// fn handle_message(
//   state: WriterState,
//   message: WriterMessage,
// ) -> actor.Next(WriterState, WriterMessage) {
//   case message {
//     Shutdown -> actor.stop()
//     Flush -> {
//       let #(pending, #(xs, ys, colors, user_ids)) =
//         deque_drain(
//           state.pending,
//           limit: None,
//           from: #([], [], [], []),
//           with: fn(acc, update) {
//             let #(xs, ys, colors, user_ids) = acc

//             let TileUpdate(x, y, color, user_id) = update

//             #([x, ..xs], [y, ..ys], [color, ..colors], [user_id, ..user_ids])
//           },
//         )

//       let assert Ok(_) = database.set_tiles(state.db, xs, ys, colors, user_ids)

//       process.send_after(state.subject, 5000, Flush)

//       let state = WriterState(..state, pending:)
//       actor.continue(state)
//     }
//     SetTile(update) -> {
//       let pending = deque.push_back(state.pending, update)
//       let state = WriterState(..state, pending:)
//       actor.continue(state)
//     }
//   }
// }

// fn deque_drain(
//   over deque: Deque(a),
//   limit limit: Option(Int),
//   from initial: acc,
//   with func: fn(acc, a) -> acc,
// ) -> #(Deque(a), acc) {
//   case limit {
//     Some(0) -> #(deque, initial)
//     Some(limit) ->
//       case deque.pop_front(deque) {
//         Ok(#(first, rest)) ->
//           deque_drain(rest, Some(limit - 1), func(initial, first), func)
//         Error(_) -> #(deque, initial)
//       }
//     None ->
//       case deque.pop_front(deque) {
//         Ok(#(first, rest)) ->
//           deque_drain(rest, None, func(initial, first), func)
//         Error(_) -> #(deque, initial)
//       }
//   }
// }

pub fn set_tile(
  board: Board,
  user: User,
  x x: Int,
  y y: Int,
  color color: Int,
) -> Result(Nil, Nil) {
  use <- bool.guard(
    x < 0 || x >= board.width || y < 0 || y >= board.height,
    return: Error(Nil),
  )

  use _ <- result.try(board_store.set_tile(
    board.store,
    x: x,
    y: y,
    color: color,
  ))

  let assert Ok(_) =
    database.set_tile(board.db, x: x, y: y, color: color, user_id: user.id)

  // process.send(
  //   board.writer,
  //   SetTile(TileUpdate(x:, y:, color:, user_id: user.id)),
  // )

  Ok(Nil)
}

pub fn to_snapshot(board: Board) -> Snapshot {
  let colors = board_store.to_bit_array(board.store)
  Snapshot(colors:, width: board.width, height: board.height)
}
