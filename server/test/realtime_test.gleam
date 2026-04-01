import client
import fixture
import gleam/erlang/process
import logging
import shared/transport

pub fn simple_user_count_test() {
  use <- fixture.using_server
  use client <- fixture.using_client

  assert client.receive(client) == Ok(transport.UserCountUpdated(count: 1))
}

pub fn user_count_broadcast_test() {
  use <- fixture.using_server

  use client1 <- fixture.using_client
  assert client.receive(client1) == Ok(transport.UserCountUpdated(count: 1))

  use client2 <- fixture.using_client
  assert client.receive(client1) == Ok(transport.UserCountUpdated(count: 2))
  assert client.receive(client2) == Ok(transport.UserCountUpdated(count: 2))
}

pub fn user_count_client_disconnect_test() {
  use <- fixture.using_server

  use client1 <- fixture.using_client
  assert client.receive(client1) == Ok(transport.UserCountUpdated(count: 1))

  use client2 <- fixture.using_client
  assert client.receive(client1) == Ok(transport.UserCountUpdated(count: 2))
  assert client.receive(client2) == Ok(transport.UserCountUpdated(count: 2))

  client.close(client1)
  assert client.receive(client2) == Ok(transport.UserCountUpdated(count: 1))
}

pub fn simple_tile_change_test() {
  use <- fixture.using_server
  use client <- fixture.using_client
  let _ = client.receive(client)

  client.send(client, transport.TileChanged(x: 0, y: 0, color: 5))

  assert client.receive(client)
    == Ok(transport.TileUpdate(x: 0, y: 0, color: 5))
}

pub fn tile_broadcast_test() {
  use <- fixture.using_server

  use client1 <- fixture.using_client
  let _ = client.receive(client1)

  use client2 <- fixture.using_client
  let _ = client.receive(client1)
  let _ = client.receive(client2)

  client.send(client1, transport.TileChanged(x: 0, y: 0, color: 5))

  assert client.receive(client1)
    == Ok(transport.TileUpdate(x: 0, y: 0, color: 5))
  assert client.receive(client2)
    == Ok(transport.TileUpdate(x: 0, y: 0, color: 5))
}

pub fn set_tile_rejects_placement_during_cooldown_test() {
  use <- fixture.using_server

  use client <- fixture.using_client
  let _ = client.receive(client)

  client.send(client, transport.TileChanged(x: 5, y: 5, color: 5))
  assert client.receive(client)
    == Ok(transport.TileUpdate(x: 5, y: 5, color: 5))

  client.send(client, transport.TileChanged(x: 6, y: 6, color: 6))
  assert client.receive(client) == Error(Nil)
}
// pub fn malicious_client_test() {
//   // TODO: issue is that using `use` with using_server means that the entire server crashes so you cant put any more code beyond this point
//   // must wrap in a callback or something
//   use <- fixture.using_server

//   use client <- fixture.using_client
//   let _ = client.receive(client)

//   client.send(client, transport.TileChanged(x: -1, y: -1, color: 0))
// }
// pub fn main() -> Nil {
//   let assert Ok(client) = client.init()

//   client.send(client, transport.TileChanged(x: -1, y: -1, color: 0))

//   client.send(client, transport.TileChanged(x: 5, y: 5, color: 0))
//   client.send(client, transport.TileChanged(x: 5, y: 5, color: 0))
//   client.send(client, transport.TileChanged(x: 5, y: 5, color: 0))

//   process.sleep_forever()
// }
