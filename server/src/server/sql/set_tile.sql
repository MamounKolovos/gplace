WITH tile AS (
  UPDATE board
  SET color = $3, updated_by = $4
  WHERE x = $1 AND y = $2
  RETURNING x, y, $3::int AS color, $4::int AS user_id
),
history AS (
  INSERT INTO board_history (x, y, color, user_id)
  SELECT x, y, color, user_id
  FROM tile
)
UPDATE users
SET tiles_placed = tiles_placed + 1, last_placed_at = $5
WHERE id = $4