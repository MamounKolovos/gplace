import lustre/effect.{type Effect}

pub fn start(to_msg: fn(Float) -> msg) -> Effect(msg) {
  use dispatch <- effect.from

  do_start(fn(dt) { to_msg(dt) |> dispatch })
}

@external(javascript, "./engine_ffi.mjs", "start")
fn do_start(on_tick tick: fn(Float) -> Nil) -> Nil

pub fn stop() -> Effect(msg) {
  use _ <- effect.from

  do_stop()
}

@external(javascript, "./engine_ffi.mjs", "stop")
fn do_stop() -> Nil
