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

pub fn move_to(camera: Camera, position: Vec2) -> Camera {
  let position =
    vec2.clamp(
      position,
      min: Vec2(-1.0 *. 1250.0, -1.0 *. 1250.0),
      max: Vec2(1250.0 *. zoom(camera), 1250.0 *. zoom(camera)),
    )
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

  // transform back from log space since the ratio is calculated in normal space
  let old_zoom = float.exponential(camera.log_zoom)
  let new_zoom = float.exponential(new_log_zoom)

  let zoom_ratio = new_zoom /. old_zoom

  // anchor point by default is (0, 0)
  // this is the formula to make the pointer the anchor point instead
  // camera * r pulls the camera towards (0, 0)
  // pointer * (r - 1) pushes the camera towards the pointer
  let new_position =
    vec2.add(
      vec2.mul(camera.position, zoom_ratio),
      vec2.mul(screen_target, zoom_ratio -. 1.0),
    )

  Camera(position: new_position, log_zoom: new_log_zoom)
}

pub fn screen_to_world(camera: Camera, position: Vec2) -> Vec2 {
  let zoom = zoom(camera)
  vec2.add(camera.position, position) |> vec2.div(zoom)
}
