insert into users(email, name, password_hash)
values ($1, $2, $3)
returning id, email, name, created_at, updated_at