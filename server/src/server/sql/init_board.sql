WITH config AS (
  INSERT INTO board_config(width, height, max_color)
  VALUES ($1, $2, $3)
  RETURNING width, height
)
INSERT INTO board(x, y, color)
-- TODO: validate that initial_color is between 0 and max_color
SELECT x, y, $4
FROM config, generate_series(0, config.width - 1) AS x,
  generate_series(0, config.height - 1) AS y;