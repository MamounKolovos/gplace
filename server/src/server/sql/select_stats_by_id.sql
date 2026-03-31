SELECT tiles_placed, last_placed_at
FROM users
WHERE id = $1;