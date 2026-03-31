-- migrate:up

ALTER TABLE users ADD COLUMN last_placed_at timestamp;
ALTER TABLE users ADD COLUMN tiles_placed integer NOT NULL DEFAULT 0 CHECK (tiles_placed >= 0);

-- migrate:down

ALTER TABLE users DROP COLUMN IF EXISTS last_placed_at;
ALTER TABLE users DROP COLUMN IF EXISTS tiles_placed;