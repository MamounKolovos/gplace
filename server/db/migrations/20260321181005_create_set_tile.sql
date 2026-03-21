-- migrate:up

CREATE OR REPLACE PROCEDURE set_tile (
  x_ INTEGER,
  y_ INTEGER,
  color_ INTEGER,
  user_id_ INTEGER
) AS $$
DECLARE
  width_ INTEGER;
  height_ INTEGER;
  max_color_ INTEGER;
BEGIN
    SELECT width, height, max_color INTO width_, height_, max_color_ FROM board_config;

    IF color_ < 0 OR color_ > max_color_ THEN
      RAISE EXCEPTION 'Color out of bounds, expected: 0-%, got: %', max_color_, color_;
    END IF;

    IF x_ < 0 OR x_ >= width_ OR y_ < 0 OR y_ >= height_ THEN
      RAISE EXCEPTION 'Coordinates out of bounds: (%, %)', x_, y_;
    END IF;

    UPDATE board
    SET color = color_, updated_by = user_id_
    WHERE x = x_ AND y = y_;

    INSERT INTO board_history (x, y, color, user_id)
    VALUES (x_, y_, color_, user_id_);
END;
$$ LANGUAGE plpgsql;

-- migrate:down

DROP PROCEDURE IF EXISTS set_tile(INTEGER, INTEGER, INTEGER, INTEGER);