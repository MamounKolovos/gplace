-- migrate:up

CREATE TABLE board (
  x INTEGER NOT NULL,
  y INTEGER NOT NULL,
  color INTEGER NOT NULL,
  updated_at TIMESTAMP NOT NULL DEFAULT NOW(),
  updated_by INTEGER,

  PRIMARY KEY (x, y),

  FOREIGN KEY (updated_by)
    REFERENCES users(id)
    ON DELETE SET NULL
);

CREATE OR REPLACE FUNCTION update_updated_at()
  returns trigger as $$
begin
  new.updated_at = NOW() at time zone 'utc';
  return new;
end
$$ language plpgsql;

CREATE TRIGGER board_updated_at
  BEFORE UPDATE OF color, updated_by ON board
  FOR EACH ROW
  execute procedure update_updated_at();

-- migrate:down

DROP TRIGGER IF EXISTS board_updated_at;
DROP FUNCTION IF EXISTS update_updated_at();
DROP TABLE IF EXISTS board;