import client/data/vec2.{type Vec2, Vec2}
import gleam/float

// ln(1)
const min_log_zoom = 0.0

// ln(100)
const max_log_zoom = 4.60517

pub opaque type Camera {
  Camera(
    position: Vec2,
    /// store in log space since wheel deltas are additive and need to be applied multiplicatively
    /// gives us smooth exponential scaling
    log_zoom: Float,
  )
}

pub fn new() -> Camera {
  Camera(position: Vec2(0.0, 0.0), log_zoom: 0.0)
}

pub fn position(camera: Camera) -> Vec2 {
  camera.position
}

pub fn zoom(camera: Camera) -> Float {
  float.exponential(camera.log_zoom)
}

pub fn pan(camera: Camera, screen_delta delta: Vec2) -> Camera {
  let position = from_screen(camera, delta)
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
    vec2.add(camera.position, vec2.div(screen_target, old_zoom))
  let world_after = vec2.add(camera.position, vec2.div(screen_target, new_zoom))

  let new_position =
    vec2.add(camera.position, vec2.sub(world_before, world_after))

  Camera(position: new_position, log_zoom: new_log_zoom)
}

pub fn from_screen(camera: Camera, position: Vec2) -> Vec2 {
  let zoom = zoom(camera)
  vec2.add(camera.position, position |> vec2.div(zoom))
}

pub fn to_screen(camera: Camera) -> Vec2 {
  let zoom = zoom(camera)
  vec2.mul(camera.position, zoom)
}
