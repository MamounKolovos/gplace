SELECT u.id, u.email, u.password_hash, u.username, u.created_at, u.updated_at
FROM users u
WHERE u.username = $1;