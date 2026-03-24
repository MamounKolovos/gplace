SELECT color
FROM board
-- row-major order matches tile_index formula:  y * width + x
ORDER BY y, x;