import client/data/vec2.{type Vec2, Vec2}
import gleam/bool
import gleam/float
import gleam/result

// ln(1)
const min_log_zoom = 0.0

// ln(100)
const max_log_zoom = 4.60517

pub opaque type Camera {
  Camera(
    position: Position,
    zoom: Float,
    tile_focus_animation: TileFocusAnimation,
  )
}

pub fn new() -> Camera {
  Camera(
    position: Position(Vec2(0.0, 0.0)),
    zoom: 1.0,
    tile_focus_animation: Inactive,
  )
}

type TileFocusAnimation {
  Inactive
  Active(
    elapsed: Float,
    duration: Float,
    start_position: Position,
    start_zoom: Float,
    target_position: Position,
    target_zoom: Float,
  )
}

///TODO: rename to zoom_to
pub fn start_tile_focus_animation(
  camera: Camera,
  duration duration: Float,
  target_position target_position: Position,
  target_zoom target_zoom: Float,
) -> Camera {
  let center_offset = vec2.div(Vec2(960.0, 540.0), target_zoom)
  let target_position = vec2.sub(target_position.vec, center_offset) |> Position

  Camera(
    ..camera,
    tile_focus_animation: Active(
      elapsed: 0.0,
      duration:,
      start_position: camera.position,
      start_zoom: camera.zoom,
      target_position:,
      target_zoom:,
    ),
  )
}

pub fn update(camera: Camera, dt: Float) -> Camera {
  case camera.tile_focus_animation {
    Inactive -> camera
    Active(
      elapsed:,
      duration:,
      start_position:,
      start_zoom:,
      target_position:,
      target_zoom:,
    ) as tile_focus_animation -> {
      let elapsed = elapsed +. dt

      use <- bool.guard(
        elapsed >=. duration,
        return: Camera(..camera, tile_focus_animation: Inactive),
      )

      let progress =
        float.clamp(elapsed /. duration, min: 0.0, max: 1.0) |> ease_out_cubic

      let new_zoom = lerp(progress, start_zoom, target_zoom)

      let focus = vec2.lerp(progress, start_position.vec, target_position.vec)

      // distance remaining
      let offset = vec2.sub(target_position.vec, focus)

      let scaled_offset = vec2.mul(offset, start_zoom /. new_zoom)

      let new_position_vec = vec2.sub(target_position.vec, scaled_offset)

      let new_position = Position(new_position_vec)

      let tile_focus_animation = Active(..tile_focus_animation, elapsed:)
      Camera(position: new_position, zoom: new_zoom, tile_focus_animation:)
    }
  }
}

fn ease_out_cubic(progress: Float) -> Float {
  let remaining = 1.0 -. progress
  1.0 -. { remaining *. remaining *. remaining }
}

fn lerp(progress: Float, start start: Float, end end: Float) -> Float {
  start +. { progress *. { end -. start } }
}

pub opaque type Position {
  Position(vec: Vec2)
}

pub fn position_from_vec(vec: Vec2) -> Position {
  Position(vec:)
}

pub fn world_to_vec(position: Position) -> Vec2 {
  position.vec
}

pub fn zoom(camera: Camera) -> Float {
  camera.zoom
}

pub fn pan(camera: Camera, screen_delta delta: Vec2) -> Camera {
  let position = screen_to_world(camera, delta)
  Camera(..camera, position:)
}

// pub fn zoom_to(camera: Camera, log_zoom: Float) -> Camera {
//   todo
// }

pub fn zoom_by(
  camera: Camera,
  delta delta: Float,
  target screen_target: Vec2,
) -> Camera {
  // convert to log space since wheel deltas are additive and need to be applied multiplicatively
  // gives us smooth exponential scaling
  let log_zoom = float.logarithm(camera.zoom) |> result.unwrap(min_log_zoom)
  let new_log_zoom =
    float.clamp(log_zoom +. delta, min: min_log_zoom, max: max_log_zoom)

  let old_zoom = camera.zoom
  let new_zoom = float.exponential(new_log_zoom)

  let world_before =
    vec2.add(camera.position.vec, vec2.div(screen_target, old_zoom))
  let world_after =
    vec2.add(camera.position.vec, vec2.div(screen_target, new_zoom))

  let new_position =
    vec2.add(camera.position.vec, vec2.sub(world_before, world_after))

  Camera(..camera, position: Position(vec: new_position), zoom: new_zoom)
}

pub fn screen_to_world(camera: Camera, position: Vec2) -> Position {
  let vec = vec2.add(camera.position.vec, position |> vec2.div(camera.zoom))
  Position(vec:)
}

pub fn to_screen(camera: Camera) -> Vec2 {
  vec2.mul(camera.position.vec, camera.zoom)
}
