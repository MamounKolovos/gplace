-- migrate:up

CREATE TABLE board_history (
  id BIGINT GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
  x INTEGER NOT NULL,
  y INTEGER NOT NULL,
  color INTEGER NOT NULL,
  user_id INTEGER,
  created_at TIMESTAMP NOT NULL DEFAULT NOW(),

  FOREIGN KEY (user_id)
   REFERENCES users(id)
   ON DELETE SET NULL

);

-- migrate:down

DROP TABLE IF EXISTS board_history;