import client
import fixture
import shared/transport

pub fn simple_user_count_test() {
  use <- fixture.with_server
  use client <- fixture.with_client

  assert client.receive(client) == transport.UserCountUpdated(count: 1)
}

pub fn user_count_broadcast_test() {
  use <- fixture.with_server

  use client1 <- fixture.with_client
  assert client.receive(client1) == transport.UserCountUpdated(count: 1)

  use client2 <- fixture.with_client
  assert client.receive(client1) == transport.UserCountUpdated(count: 2)
  assert client.receive(client2) == transport.UserCountUpdated(count: 2)
}

pub fn user_count_client_disconnect_test() {
  use <- fixture.with_server

  use client1 <- fixture.with_client
  assert client.receive(client1) == transport.UserCountUpdated(count: 1)

  use client2 <- fixture.with_client
  assert client.receive(client1) == transport.UserCountUpdated(count: 2)
  assert client.receive(client2) == transport.UserCountUpdated(count: 2)

  client.close(client1)
  assert client.receive(client2) == transport.UserCountUpdated(count: 1)
}

pub fn simple_tile_change_test() {
  use <- fixture.with_server
  use client <- fixture.with_client
  let _ = client.receive(client)

  client.send(client, transport.TileChanged(x: 0, y: 0, color: 5))

  assert client.receive(client) == transport.TileUpdate(x: 0, y: 0, color: 5)
}

pub fn tile_broadcast_test() {
  use <- fixture.with_server

  use client1 <- fixture.with_client
  let _ = client.receive(client1)

  use client2 <- fixture.with_client
  let _ = client.receive(client1)
  let _ = client.receive(client2)

  client.send(client1, transport.TileChanged(x: 0, y: 0, color: 5))

  assert client.receive(client1) == transport.TileUpdate(x: 0, y: 0, color: 5)
  assert client.receive(client2) == transport.TileUpdate(x: 0, y: 0, color: 5)
}
