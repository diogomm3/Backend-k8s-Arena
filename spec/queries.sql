-- ============================================================
-- Backend-k8s-Arena canonical SQL
-- One statement per endpoint. Parameters are positional ($1, $2…).
-- ALL parameters are explicitly cast (::int, ::text) so strict
-- drivers (asyncpg, pgx) and lenient ones behave identically.
-- ALL counts are cast to ::int — no bigint reaches responses.
-- CI verbatim check: compares statements ignoring `--` comment lines
-- and surrounding whitespace (leading/trailing, blank lines).
-- ============================================================

-- name: health
-- No database query. App returns { "status": "ok" }.

-- name: feed
-- Returns the 20 newest posts with author and like count.
-- Ordering: created_at DESC, id DESC (tie-break).
WITH recent AS (
  SELECT id, user_id, content, created_at
  FROM posts
  ORDER BY created_at DESC, id DESC
  LIMIT 20
)
SELECT r.id, r.user_id, r.content,
       to_char(r.created_at AT TIME ZONE 'UTC', 'YYYY-MM-DD"T"HH24:MI:SS.MS"Z"') AS created_at,
       u.username,
       COALESCE(l.cnt, 0)::int AS like_count
FROM recent r
JOIN users u ON u.id = r.user_id
LEFT JOIN LATERAL (
  SELECT COUNT(*)::int AS cnt FROM likes WHERE post_id = r.id
) l ON true
ORDER BY r.created_at DESC, r.id DESC;

-- name: get_post
-- Returns one post with author and like count, or 0 rows if not found.
WITH target AS (
  SELECT id, user_id, content, created_at
  FROM posts
  WHERE id = $1::int
)
SELECT t.id, t.user_id, t.content,
       to_char(t.created_at AT TIME ZONE 'UTC', 'YYYY-MM-DD"T"HH24:MI:SS.MS"Z"') AS created_at,
       u.username,
       COALESCE(l.cnt, 0)::int AS like_count
FROM target t
JOIN users u ON u.id = t.user_id
LEFT JOIN LATERAL (
  SELECT COUNT(*)::int AS cnt FROM likes WHERE post_id = t.id
) l ON true;

-- name: create_post
-- Params: $1=user_id::int, $2=content::text
-- Returns created post with author and like_count=0.
WITH ins AS (
  INSERT INTO posts (user_id, content) VALUES ($1::int, $2::text)
  RETURNING id, user_id, content, created_at
)
SELECT i.id, i.user_id, i.content,
       to_char(i.created_at AT TIME ZONE 'UTC', 'YYYY-MM-DD"T"HH24:MI:SS.MS"Z"') AS created_at,
       u.username, 0::int AS like_count
FROM ins i
JOIN users u ON u.id = i.user_id;

-- name: like_post
-- Params: $1=post_id::int, $2=user_id::int
-- Idempotent: first like inserts, repeat like no-ops.
-- Returns { "post_id": N, "like_count": M }.
-- Returns 0 rows if post not found → app maps to 404.
WITH ins AS (
  INSERT INTO likes (post_id, user_id)
  SELECT p.id, $2::int FROM posts p WHERE p.id = $1::int
  ON CONFLICT (post_id, user_id) DO NOTHING
  RETURNING 1 AS inserted
), cnt AS (
  SELECT COUNT(*)::int AS n FROM likes WHERE post_id = $1::int
)
SELECT $1::int AS post_id,
       cnt.n + COALESCE((SELECT 1 FROM ins), 0) AS like_count
FROM cnt
WHERE EXISTS (SELECT 1 FROM posts WHERE id = $1::int);