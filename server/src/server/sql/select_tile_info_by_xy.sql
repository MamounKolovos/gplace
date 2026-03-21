SELECT b.updated_at, u.username
FROM board b
LEFT JOIN users u ON b.updated_by = u.id
WHERE b.x = $1 AND b.y = $2;