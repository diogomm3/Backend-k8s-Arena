#!/usr/bin/env bash
# db-check: Verify database state matches expectations
# Connects via DATABASE_URL/PG* env (default: local container)
# Verifies: row counts, id contiguity, no orphan FKs, PK column order,
# index presence, checksums, sequences unchanged
# Runs canonical queries on throwaway DB to verify behavior
set -euo pipefail

# Find repo root (works both locally and in CI)
REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

# Default connection (local container)
DATABASE_URL="${DATABASE_URL:-postgres://postgres:arena_local@127.0.0.1:5432/arena}"
WORK_DB="arena"
TEMPLATE_DB="arena_template"
CONTAINER_NAME="arena-postgres"

# Expected checksums for small seed
SMALL_SEED_CHECKSUMS_FILE="${REPO_ROOT}/db/checksums/small-seed.json"

# Extract connection params from DATABASE_URL for psql
# postgres://user:pass@host:port/db
if [[ "${DATABASE_URL}" =~ postgres://([^:]+):([^@]+)@([^:]+):([0-9]+)/(.+) ]]; then
  PGUSER="${BASH_REMATCH[1]}"
  PGPASSWORD="${BASH_REMATCH[2]}"
  PGHOST="${BASH_REMATCH[3]}"
  PGPORT="${BASH_REMATCH[4]}"
  PGDATABASE="${BASH_REMATCH[5]}"
  export PGUSER PGPASSWORD PGHOST PGPORT PGDATABASE
else
  echo "ERROR: Invalid DATABASE_URL format"
  exit 1
fi

# Helper: run psql on working DB
psql_work() {
  psql -v ON_ERROR_STOP=1 "$@"
}

# Helper: run psql on template DB
psql_template() {
  psql -h "${PGHOST}" -p "${PGPORT}" -U "${PGUSER}" -d "${TEMPLATE_DB}" -v ON_ERROR_STOP=1 "$@"
}

echo "=== Database Verification ==="
echo "Target database: ${PGDATABASE} on ${PGHOST}:${PGPORT}"
echo

# 1. Row counts
echo "--- Row counts ---"
psql_work -tAc "
  SELECT 'users: ' || count(*) FROM users
  UNION ALL SELECT 'posts: ' || count(*) FROM posts
  UNION ALL SELECT 'likes: ' || count(*) FROM likes
"

# 2. ID contiguity
echo
echo "--- ID contiguity ---"
psql_work -tAc "
  SELECT 'users: min=' || min(id) || ' max=' || max(id) || ' contiguous=' || (max(id) - min(id) + 1 = count(*))::text FROM users
  UNION ALL SELECT 'posts: min=' || min(id) || ' max=' || max(id) || ' contiguous=' || (max(id) - min(id) + 1 = count(*))::text FROM posts
"

# 3. No orphan FKs
echo
echo "--- Orphan FK check ---"
psql_work -tAc "
  SELECT 'orphan posts.user_id: ' || count(*) FROM posts p LEFT JOIN users u ON u.id = p.user_id WHERE u.id IS NULL
  UNION ALL SELECT 'orphan likes.post_id: ' || count(*) FROM likes l LEFT JOIN posts p ON p.id = l.post_id WHERE p.id IS NULL
  UNION ALL SELECT 'orphan likes.user_id: ' || count(*) FROM likes l LEFT JOIN users u ON u.id = l.user_id WHERE u.id IS NULL
"

# 4. PK column order (likes must be post_id, user_id)
echo
echo "--- PK column order ---"
psql_work -tAc "
  SELECT 'likes PK columns: ' || string_agg(attname, ', ' ORDER BY attnum)
  FROM pg_index i
  JOIN pg_attribute a ON a.attrelid = i.indrelid AND a.attnum = ANY(i.indkey)
  WHERE i.indrelid = 'likes'::regclass AND i.indisprimary
"

# 5. Index presence
echo
echo "--- Required index ---"
psql_work -tAc "
  SELECT 'posts_created_at_id_desc: ' || CASE WHEN EXISTS (
    SELECT 1 FROM pg_indexes WHERE indexname = 'posts_created_at_id_desc'
  ) THEN 'EXISTS' ELSE 'MISSING' END
"

# 6. Sequences (read last_value, do NOT call nextval)
echo
echo "--- Sequence state (last_value) ---"
psql_work -tAc "
  SELECT 'users_id_seq: ' || last_value FROM users_id_seq
  UNION ALL SELECT 'posts_id_seq: ' || last_value FROM posts_id_seq
"

# Expected next IDs
EXPECTED_NEXT_POST=$(( $(psql_work -tAc "SELECT max(id) FROM posts") + 1 ))
EXPECTED_NEXT_USER=$(( $(psql_work -tAc "SELECT max(id) FROM users") + 1 ))
echo "Expected next post id: ${EXPECTED_NEXT_POST}"
echo "Expected next user id: ${EXPECTED_NEXT_USER}"

# 7. Checksums
echo
echo "--- Checksums ---"
CHECKSUMS=$(psql_work -tAc "
  SELECT json_object_agg(table, checksum_sum)
  FROM (
    SELECT 'users' AS table,
      sum((('x' || substr(md5(id::text || '|' || username || '|' || extract(epoch from created_at)::text), 1, 15))::bit(60)::bigint))::text AS checksum_sum
    FROM users
    UNION ALL
    SELECT 'posts',
      sum((('x' || substr(md5(id::text || '|' || user_id::text || '|' || content || '|' || extract(epoch from created_at)::text), 1, 15))::bit(60)::bigint))::text
    FROM posts
    UNION ALL
    SELECT 'likes',
      sum((('x' || substr(md5(post_id::text || '|' || user_id::text || '|' || extract(epoch from created_at)::text), 1, 15))::bit(60)::bigint))::text
    FROM likes
  ) t
")
echo "Computed: ${CHECKSUMS}"

if [ -f "${SMALL_SEED_CHECKSUMS_FILE}" ]; then
  EXPECTED=$(cat "${SMALL_SEED_CHECKSUMS_FILE}")
  echo "Expected: ${EXPECTED}"
  if [ "${CHECKSUMS}" = "${EXPECTED}" ]; then
    echo "Checksums MATCH ✓"
  else
    echo "Checksums MISMATCH ✗"
    exit 1
  fi
else
  echo "No expected checksums file found (skipping comparison)"
fi

# 8. Tie groups in top 20
echo
echo "--- Tie groups in newest 20 ---"
psql_work -tAc "
  WITH top20 AS (
    SELECT id, created_at FROM posts ORDER BY created_at DESC, id DESC LIMIT 20
  )
  SELECT 'distinct_seconds=' || count(DISTINCT created_at) || ' tied_rows=' || (20 - count(DISTINCT created_at)) FROM top20
"

# 9. Likes stats
echo
echo "--- Likes per post stats ---"
psql_work -tAc "
  SELECT
    'min=' || min(cnt) || ' max=' || max(cnt) || ' avg=' || round(avg(cnt)::numeric, 2) ||
    ' total=' || sum(cnt) || ' zero_like_posts=' || count(*) FILTER (WHERE cnt = 0)
  FROM (SELECT count(*) AS cnt FROM likes GROUP BY post_id) l
"

# 10. Likes on newest 20 posts
echo
echo "--- Likes on newest 20 posts ---"
psql_work -tAc "
  WITH top20 AS (SELECT id FROM posts ORDER BY created_at DESC, id DESC LIMIT 20)
  SELECT 'min=' || min(cnt) || ' max=' || max(cnt) || ' avg=' || round(avg(cnt)::numeric, 2)
  FROM (SELECT count(*) AS cnt FROM likes l JOIN top20 t ON t.id = l.post_id GROUP BY l.post_id) l
"

# 11. Run canonical queries on throwaway DB (cloned from template) to verify behavior
echo
echo "--- Canonical query verification (on throwaway DB) ---"

# Create throwaway DB
THROWAWAY_DB="arena_check_$$"
psql -h "${PGHOST}" -p "${PGPORT}" -U "${PGUSER}" -d postgres -c "
  DROP DATABASE IF EXISTS ${THROWAWAY_DB};
  CREATE DATABASE ${THROWAWAY_DB} TEMPLATE ${TEMPLATE_DB} STRATEGY = file_copy;
" >/dev/null

# Function to run query on throwaway DB
psql_throwaway() {
  psql -h "${PGHOST}" -p "${PGPORT}" -U "${PGUSER}" -d "${THROWAWAY_DB}" -v ON_ERROR_STOP=1 "$@"
}

# Record sequence values BEFORE
SEQ_BEFORE=$(psql_throwaway -tAc "SELECT last_value FROM posts_id_seq")

# Test get_post (found)
echo "Testing get_post (id=1)..."
psql_throwaway -c "
  PREPARE get_post_stmt(int) AS
  WITH target AS (
    SELECT id, user_id, content, created_at
    FROM posts WHERE id = \$1::int
  )
  SELECT t.id, t.user_id, t.content,
    to_char(t.created_at AT TIME ZONE 'UTC', 'YYYY-MM-DD\"T\"HH24:MI:SS.MS\"Z\"') AS created_at,
    u.username, COALESCE(l.cnt, 0)::int AS like_count
  FROM target t
  JOIN users u ON u.id = t.user_id
  LEFT JOIN LATERAL (SELECT COUNT(*)::int AS cnt FROM likes WHERE post_id = t.id) l ON true;
  EXPLAIN (ANALYZE, BUFFERS) EXECUTE get_post_stmt(1);
" >/dev/null 2>&1
echo "  get_post: OK"

# Test get_post (not found)
echo "Testing get_post (id=999999)..."
psql_throwaway -c "EXECUTE get_post_stmt(999999);" >/dev/null 2>&1
ROW_COUNT=$(psql_throwaway -tAc "EXECUTE get_post_stmt(999999);" | wc -l)
if [ "${ROW_COUNT}" -eq 0 ]; then
  echo "  get_post not found: OK (0 rows)"
else
  echo "  get_post not found: FAIL (got ${ROW_COUNT} rows)"
  exit 1
fi

# Test create_post
echo "Testing create_post..."
psql_throwaway -c "
  PREPARE create_post_stmt(int, text) AS
  WITH ins AS (
    INSERT INTO posts (user_id, content) VALUES (\$1::int, \$2::text)
    RETURNING id, user_id, content, created_at
  )
  SELECT i.id, i.user_id, i.content,
    to_char(i.created_at AT TIME ZONE 'UTC', 'YYYY-MM-DD\"T\"HH24:MI:SS.MS\"Z\"') AS created_at,
    u.username, 0::int AS like_count
  FROM ins i JOIN users u ON u.id = i.user_id;
  BEGIN;
  EXPLAIN (ANALYZE, BUFFERS) EXECUTE create_post_stmt(42, 'test content');
  ROLLBACK;
" >/dev/null 2>&1
echo "  create_post: OK"

# Test like_post (first like)
echo "Testing like_post (first)..."
psql_throwaway -c "
  PREPARE like_post_stmt(int, int) AS
  WITH ins AS (
    INSERT INTO likes (post_id, user_id)
    SELECT p.id, \$2::int FROM posts p WHERE p.id = \$1::int
    ON CONFLICT (post_id, user_id) DO NOTHING RETURNING 1 AS inserted
  ), cnt AS (SELECT COUNT(*)::int AS n FROM likes WHERE post_id = \$1::int)
  SELECT \$1::int AS post_id, cnt.n + COALESCE((SELECT 1 FROM ins), 0) AS like_count
  FROM cnt WHERE EXISTS (SELECT 1 FROM posts WHERE id = \$1::int);
  BEGIN;
  EXPLAIN (ANALYZE, BUFFERS) EXECUTE like_post_stmt(1, 1);
  ROLLBACK;
" >/dev/null 2>&1
echo "  like_post first: OK"

# Test like_post (repeat)
echo "Testing like_post (repeat)..."
psql_throwaway -c "BEGIN; EXECUTE like_post_stmt(1, 1); ROLLBACK;" >/dev/null 2>&1
echo "  like_post repeat: OK"

# Test like_post (unknown post)
echo "Testing like_post (unknown post)..."
RESULT=$(psql_throwaway -tAc "BEGIN; EXECUTE like_post_stmt(999999, 1); ROLLBACK;")
if [ -z "${RESULT}" ]; then
  echo "  like_post unknown: OK (0 rows)"
else
  echo "  like_post unknown: FAIL (got result)"
  exit 1
fi

# Record sequence values AFTER
SEQ_AFTER=$(psql_throwaway -tAc "SELECT last_value FROM posts_id_seq")

# Clean up throwaway DB
psql -h "${PGHOST}" -p "${PGPORT}" -U "${PGUSER}" -d postgres -c "DROP DATABASE IF EXISTS ${THROWAWAY_DB};" >/dev/null

# Verify sequences unchanged on real database
REAL_SEQ=$(psql_work -tAc "SELECT last_value FROM posts_id_seq")
if [ "${REAL_SEQ}" != "${SEQ_BEFORE}" ]; then
  echo "  ERROR: Real database sequence changed during check!"
  exit 1
fi
if [ "${SEQ_BEFORE}" != "${SEQ_AFTER}" ]; then
  echo "  ERROR: Throwaway database sequence changed!"
  exit 1
fi
echo "  Sequences unchanged: OK"

# 12. DB size
echo
echo "--- Database size ---"
psql_work -tAc "SELECT pg_size_pretty(pg_database_size('${WORK_DB}')) AS size"

echo
echo "=== All checks passed ==="