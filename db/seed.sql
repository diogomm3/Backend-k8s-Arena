-- Backend-k8s-Arena deterministic seed
-- Pure SQL, fully deterministic across runs and Postgres versions
-- Uses md5() for pseudo-randomness (stable across versions)
-- All timestamps explicit, no now()/DEFAULT now()
-- Parameters: \set n_users, \set n_posts, \set n_likes_total
-- Defaults applied only when not provided

\set TIME ZONE 'UTC'

-- Default parameters (full seed)
\if :{?n_users} \else \set n_users 50000 \endif
\if :{?n_posts} \else \set n_posts 500000 \endif
\if :{?n_likes_total} \else \set n_likes_total 2000000 \endif

-- Helper: non-negative 60-bit integer from md5
-- ('x' || substr(md5(...), 1, 15))::bit(60)::bigint  -- 15 hex = 60 bits, always >= 0

-- ============================================================
-- USERS: 1..n_users, contiguous, deterministic usernames
-- ============================================================
INSERT INTO users (id, username, created_at)
SELECT
  g,
  'user' || g,
  '2020-01-01 00:00:00+00'::timestamptz
FROM generate_series(1, :n_users) g;

-- ============================================================
-- POSTS: 1..n_posts, contiguous
-- user_id: hash-based distribution
-- content: templates with variations, 1..280 code points, no U+0000
-- created_at: explicit, with tie groups (every 4 consecutive ids share same second)
-- ============================================================

-- Content templates (indexed by hash for variation)
WITH content_templates AS (
  SELECT 1 AS idx, E'Just finished reading a great book!' AS content
  UNION ALL SELECT 2, E'Working on a new project, stay tuned.'
  UNION ALL SELECT 3, E'Coffee is life ☕'
  UNION ALL SELECT 4, E'Beautiful sunset today 🌅'
  UNION ALL SELECT 5, E'Learning something new every day.'
  UNION ALL SELECT 6, E'Weekend plans? 🤔'
  UNION ALL SELECT 7, E'Bug fixed after 5 hours. Worth it.'
  UNION ALL SELECT 8, E'Deploy successful! 🚀'
  UNION ALL SELECT 9, E'Code review time.'
  UNION ALL SELECT 10, E'Refactoring legacy code...'
  UNION ALL SELECT 11, E'New feature shipped!'
  UNION ALL SELECT 12, E'Database migration complete.'
  UNION ALL SELECT 13, E'Performance improved by 40%.'
  UNION ALL SELECT 14, E'Writing tests for the new API.'
  UNION ALL SELECT 15, E'Documentation updated.'
  UNION ALL SELECT 16, E'Hello world! 👋'
  UNION ALL SELECT 17, E'Testing the new deployment pipeline.'
  UNION ALL SELECT 18, E'Great talk at the conference today.'
  UNION ALL SELECT 19, E'Pair programming session was productive.'
  UNION ALL SELECT 20, E'Quick standup, then back to coding.'
  UNION ALL SELECT 21, E'Migrating to the new framework.'
  UNION ALL SELECT 22, E'Security audit passed. ✅'
  UNION ALL SELECT 23, E'Adding integration tests.'
  UNION ALL SELECT 24, E'Optimizing the query planner.'
  UNION ALL SELECT 25, E'New monitoring dashboard live.'
  UNION ALL SELECT 26, E'Code freeze for release.'
  UNION ALL SELECT 27, E'Hotfix deployed to production.'
  UNION ALL SELECT 28, E'Reviewing PR #1247.'
  UNION ALL SELECT 29, E'Breaking changes in v2.0.'
  UNION ALL SELECT 30, E'Backward compatibility maintained.'
  UNION ALL SELECT 31, E'中文测试内容 🎉'
  UNION ALL SELECT 32, E'Contenu français avec accents.'
  UNION ALL SELECT 33, E'日本語のテスト投稿です。'
  UNION ALL SELECT 34, E'Special chars: <>&"\'\\n\\t\\\\'
  UNION ALL SELECT 35, E'Emoji stress test: 😀😃😄😁😆😅😂🤣😊😇'
  UNION ALL SELECT 36, E'Mixed: Hello 世界 🌍'
  UNION ALL SELECT 37, E'Quote test: "quoted" and ''single'''
  UNION ALL SELECT 38, E'Newline' || chr(10) || 'tab' || chr(9) || 'test'
  UNION ALL SELECT 39, E'Backslash \\\\ and forward slash /'
  UNION ALL SELECT 40, E'Angle brackets <script>alert(1)</script>'
),
-- Generate posts with deterministic attributes
post_gen AS (
  SELECT
    g AS id,
    (('x' || substr(md5('post_user' || g::text), 1, 15))::bit(60)::bigint % :n_users) + 1 AS user_id,
    ct.content ||
    CASE
      WHEN (('x' || substr(md5('post_content_var' || g::text), 1, 15))::bit(60)::bigint % 10) = 0
      THEN ' #' || (('x' || substr(md5('post_content_hash' || g::text), 1, 8))::bit(32)::bigint % 10000)::text
      ELSE ''
    END AS content,
    ('2020-01-01 00:00:00+00'::timestamptz
      + (floor((g - 1) / 5000.0) || ' days')::interval
      + (floor((g - 1) / 4.0) % 86400 || ' seconds')::interval) AS created_at
  FROM generate_series(1, :n_posts) g
  CROSS JOIN LATERAL (
    SELECT content FROM content_templates
    WHERE idx = 1 + (('x' || substr(md5('post_template' || g::text), 1, 15))::bit(60)::bigint % 40)
  ) ct
)
INSERT INTO posts (id, user_id, content, created_at)
SELECT id, user_id, content, created_at FROM post_gen;

-- ============================================================
-- LIKES: exact n_likes_total, no duplicate (post_id, user_id)
-- Popularity independent of recency: heavy set chosen by hash
-- Per-post count <= n_users, exact total, stride coprime to n_users
-- ============================================================

-- Step 1: Assign each post a popularity weight (independent of id/recency)
-- Heavy threshold = 0.2 * 2^60 = 230584300921369395 (use numeric to avoid overflow)
WITH post_weights AS (
  SELECT
    id AS post_id,
    CASE
      WHEN (('x' || substr(md5('post_popularity' || id::text), 1, 15))::bit(60)::bigint)::numeric < 230584300921369395
      THEN 10.0 ELSE 1.0
    END AS weight
  FROM posts
),
-- Step 2: Compute target likes per post proportional to weight
likes_per_post AS (
  SELECT
    post_id,
    weight,
    floor(:n_likes_total * weight / sum(weight) OVER ())::bigint AS base_likes
  FROM post_weights
),
-- Step 3: Distribute remainder to exact total
remainder_alloc AS (
  SELECT
    post_id,
    base_likes +
    CASE
      WHEN row_number() OVER (ORDER BY (('x' || substr(md5('remainder_order' || post_id::text), 1, 15))::bit(60)::bigint)) <=
           :n_likes_total - sum(base_likes) OVER ()
      THEN 1 ELSE 0
    END AS target_likes
  FROM likes_per_post
),
-- Step 4: Clamp to n_users and track excess
clamped AS (
  SELECT
    post_id,
    LEAST(target_likes, :n_users) AS clamped_likes,
    GREATEST(target_likes - :n_users, 0) AS excess
  FROM remainder_alloc
),
-- Step 5: Compute total excess and eligible posts for redistribution
excess_info AS (
  SELECT
    sum(excess) AS total_excess,
    count(*) FILTER (WHERE clamped_likes < :n_users) AS eligible_count
  FROM clamped
),
-- Step 6: Redistribute excess to posts with room
redistrib AS (
  SELECT
    c.post_id,
    c.clamped_likes,
    CASE
      WHEN c.clamped_likes < :n_users AND ei.total_excess > 0 AND ei.eligible_count > 0
      THEN LEAST(
        :n_users - c.clamped_likes,
        floor(ei.total_excess *
          (('x' || substr(md5('redistrib' || c.post_id::text), 1, 15))::bit(60)::bigint)::numeric /
          ei.eligible_count)::bigint
      )
      ELSE 0
    END AS extra_likes
  FROM clamped c
  CROSS JOIN excess_info ei
),
final_likes AS (
  SELECT
    post_id,
    clamped_likes + extra_likes AS final_likes
  FROM redistrib
),
-- Step 7: stride = smallest integer > 1 coprime to n_users
stride AS (
  SELECT (CASE
    WHEN gcd(2::bigint, :n_users::bigint) = 1 THEN 2
    WHEN gcd(3::bigint, :n_users::bigint) = 1 THEN 3
    WHEN gcd(5::bigint, :n_users::bigint) = 1 THEN 5
    WHEN gcd(7::bigint, :n_users::bigint) = 1 THEN 7
    WHEN gcd(11::bigint, :n_users::bigint) = 1 THEN 11
    WHEN gcd(13::bigint, :n_users::bigint) = 1 THEN 13
    WHEN gcd(17::bigint, :n_users::bigint) = 1 THEN 17
    WHEN gcd(19::bigint, :n_users::bigint) = 1 THEN 19
    WHEN gcd(23::bigint, :n_users::bigint) = 1 THEN 23
    ELSE 29
  END) AS s
),
like_rows AS (
  SELECT
    fl.post_id,
    u AS user_id,
    p.created_at + '1 second'::interval + ((u - 1) % 60 || ' seconds')::interval AS created_at
  FROM final_likes fl
  JOIN posts p ON p.id = fl.post_id
  CROSS JOIN LATERAL (
    SELECT (('x' || substr(md5('like_offset' || fl.post_id::text), 1, 15))::bit(60)::bigint % :n_users) + 1 AS offset
  ) o
  CROSS JOIN stride
  CROSS JOIN LATERAL generate_series(0, fl.final_likes - 1) AS i
  CROSS JOIN LATERAL (
    SELECT (o.offset + i * stride.s - 1) % :n_users + 1 AS u
  ) u
)
INSERT INTO likes (post_id, user_id, created_at)
SELECT post_id, user_id, created_at FROM like_rows;

-- ============================================================
-- SEQUENCES: set so nextval = max(id) + 1
-- ============================================================
SELECT setval('users_id_seq', :n_users);
SELECT setval('posts_id_seq', :n_posts);

-- ============================================================
-- VERIFICATION OUTPUT
-- ============================================================
SELECT 'users' AS table, count(*) AS rows FROM users
UNION ALL SELECT 'posts', count(*) FROM posts
UNION ALL SELECT 'likes', count(*) FROM likes;

SELECT 'users' AS table, min(id) AS min_id, max(id) AS max_id,
  max(id) - min(id) + 1 = count(*) AS contiguous FROM users
UNION ALL SELECT 'posts', min(id), max(id),
  max(id) - min(id) + 1 = count(*) FROM posts;

SELECT
  'tie_groups_in_top20' AS check,
  count(DISTINCT created_at) AS distinct_seconds,
  20 - count(DISTINCT created_at) AS tied_rows
FROM (
  SELECT id, created_at FROM posts ORDER BY created_at DESC, id DESC LIMIT 20
) top20;

SELECT
  'likes_per_post' AS stat,
  min(cnt) AS min_likes,
  max(cnt) AS max_likes,
  avg(cnt)::numeric(10,2) AS avg_likes,
  sum(cnt) AS total_likes,
  count(*) FILTER (WHERE cnt = 0) AS zero_like_posts
FROM (SELECT count(*) AS cnt FROM likes GROUP BY post_id) l;

WITH top20 AS (
  SELECT id FROM posts ORDER BY created_at DESC, id DESC LIMIT 20
)
SELECT
  'newest_20_likes' AS stat,
  min(cnt) AS min_likes,
  max(cnt) AS max_likes,
  avg(cnt)::numeric(10,2) AS avg_likes
FROM (
  SELECT count(*) AS cnt FROM likes l JOIN top20 t ON t.id = l.post_id GROUP BY l.post_id
) l;

SELECT 'users' AS table,
  sum((('x' || substr(md5(id::text || '|' || username || '|' || extract(epoch from created_at)::text), 1, 15))::bit(60)::bigint))::text AS checksum_sum,
  count(*) AS rows
FROM users
UNION ALL
SELECT 'posts',
  sum((('x' || substr(md5(id::text || '|' || user_id::text || '|' || content || '|' || extract(epoch from created_at)::text), 1, 15))::bit(60)::bigint))::text,
  count(*)
FROM posts
UNION ALL
SELECT 'likes',
  sum((('x' || substr(md5(post_id::text || '|' || user_id::text || '|' || extract(epoch from created_at)::text), 1, 15))::bit(60)::bigint))::text,
  count(*)
FROM likes;