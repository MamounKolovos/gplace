import client/data/vec2.{type Vec2, Vec2}
import gleam/float

// ln(1)
const min_log_zoom = 0.0

// ln(100)
const max_log_zoom = 4.60517

pub opaque type Camera {
  Camera(
    position: Position,
    /// store in log space since wheel deltas are additive and need to be applied multiplicatively
    /// gives us smooth exponential scaling
    log_zoom: Float,
  )
}

pub opaque type Position {
  Position(vec: Vec2)
}

pub fn world_to_vec(position: Position) -> Vec2 {
  position.vec
}

pub fn new() -> Camera {
  Camera(position: Position(Vec2(0.0, 0.0)), log_zoom: 0.0)
}

pub fn zoom(camera: Camera) -> Float {
  float.exponential(camera.log_zoom)
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
  let new_log_zoom =
    float.clamp(camera.log_zoom +. delta, min: min_log_zoom, max: max_log_zoom)

  let old_zoom = float.exponential(camera.log_zoom)
  let new_zoom = float.exponential(new_log_zoom)

  let world_before =
    vec2.add(camera.position.vec, vec2.div(screen_target, old_zoom))
  let world_after =
    vec2.add(camera.position.vec, vec2.div(screen_target, new_zoom))

  let new_position =
    vec2.add(camera.position.vec, vec2.sub(world_before, world_after))

  Camera(position: Position(vec: new_position), log_zoom: new_log_zoom)
}

pub fn screen_to_world(camera: Camera, position: Vec2) -> Position {
  let zoom = zoom(camera)
  let vec = vec2.add(camera.position.vec, position |> vec2.div(zoom))
  Position(vec:)
}

pub fn to_screen(camera: Camera) -> Vec2 {
  let zoom = zoom(camera)
  vec2.mul(camera.position.vec, zoom)
}
