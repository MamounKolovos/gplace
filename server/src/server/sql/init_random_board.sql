WITH config AS (
  INSERT INTO board_config(width, height, max_color)
  VALUES ($1, $2, $3)
  ON CONFLICT DO NOTHING
  RETURNING width, height, max_color
)
INSERT INTO board(x, y, color)
SELECT x, y, random(0, config.max_color)
FROM config, generate_series(0, config.width - 1) AS x,
  generate_series(0, config.height - 1) AS y;
