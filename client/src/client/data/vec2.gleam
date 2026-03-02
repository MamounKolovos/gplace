pub type Vec2 {
  Vec2(x: Float, y: Float)
}

pub fn add(a: Vec2, b: Vec2) -> Vec2 {
  Vec2(a.x +. b.x, a.y +. b.y)
}

pub fn sub(a: Vec2, b: Vec2) -> Vec2 {
  Vec2(a.x -. b.x, a.y -. b.y)
}

pub fn mul(a: Vec2, scale: Float) -> Vec2 {
  Vec2(a.x *. scale, a.y *. scale)
}

pub fn neg(a: Vec2) -> Vec2 {
  Vec2(-1.0 *. a.x, -1.0 *. a.y)
}
