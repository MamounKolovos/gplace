WITH updates AS (
  UPDATE board
  SET color = u.color, updated_by = u.user_id
  FROM unnest($1::int[], $2::int[], $3::int[], $4::int[])
    AS u(x, y, color, user_id)
  WHERE board.x = u.x AND board.y = u.y
  RETURNING board.x, board.y, u.color, u.user_id
)
INSERT INTO board_history (x, y, color, user_id)
SELECT x, y, color, user_id 
FROM updates;