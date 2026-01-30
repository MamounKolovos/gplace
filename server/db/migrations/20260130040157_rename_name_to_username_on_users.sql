-- migrate:up

ALTER TABLE users RENAME COLUMN name TO username;

-- migrate:down

ALTER TABLE users RENAME COLUMN username TO name;