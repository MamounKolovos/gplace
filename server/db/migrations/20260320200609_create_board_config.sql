-- migrate:up

CREATE TABLE board_config (
  id INTEGER PRIMARY KEY DEFAULT 1,
  width INTEGER NOT NULL,
  height INTEGER NOT NULL,
  max_color INTEGER NOT NULL,

  CHECK (id = 1),
  CHECK (width > 0 AND height > 0),
  CHECK (max_color >= 0)
);

-- migrate:down

DROP TABLE IF EXISTS board_config;