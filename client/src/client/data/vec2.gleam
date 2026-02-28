pub type Vec2 {
  Vec2(x: Float, y: Float)
}

//TODO: prob redundant, using constructor directly is less chars than `vec2.new`
pub fn new(x: Float, y: Float) -> Vec2 {
  Vec2(x, y)
}

pub fn add(a: Vec2, b: Vec2) -> Vec2 {
  Vec2(a.x +. b.x, a.y +. b.y)
}

pub fn sub(a: Vec2, b: Vec2) -> Vec2 {
  Vec2(a.x -. b.x, a.y -. b.y)
}
