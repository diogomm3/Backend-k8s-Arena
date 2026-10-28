#!/usr/bin/env bash
# db-seed: Seed the template database
set -euo pipefail

FORCE=false
for arg in "$@"; do
  case $arg in
    --force) FORCE=true ;;
    *) echo "Unknown argument: $arg"; exit 1 ;;
  esac
done

CONTAINER_NAME="arena-postgres"
TEMPLATE_DB="arena_template"
SEED_START=$(date +%s)

# Check if container is running
if ! docker ps --format '{{.Names}}' | grep -q "^${CONTAINER_NAME}$"; then
  echo "ERROR: Container ${CONTAINER_NAME} not running. Run db-up first."
  exit 1
fi

# Check if template already has data
TABLE_COUNT=$(docker exec "${CONTAINER_NAME}" psql -U postgres -d "${TEMPLATE_DB}" -tAc "
  SELECT count(*) FROM information_schema.tables WHERE table_schema='public' AND table_name IN ('users','posts','likes')
" 2>/dev/null || echo 0)

if [ "${TABLE_COUNT}" -eq 3 ] && [ "${FORCE}" = false ]; then
  echo "Template database already seeded. Use --force to reseed."
  exit 0
fi

echo "Seeding template database (this may take a while for full seed)..."

# Apply schema first
docker exec -i "${CONTAINER_NAME}" psql -U postgres -d "${TEMPLATE_DB}" -v ON_ERROR_STOP=1 < /home/diogo/Backend-k8s-Arena/db/schema.sql

# Run seed with optional parameter overrides
# Allow CI to override via env: N_USERS, N_POSTS, N_LIKES_TOTAL
PSQL_VARS=()
[ -n "${N_USERS:-}" ] && PSQL_VARS+=("-v" "n_users=${N_USERS}")
[ -n "${N_POSTS:-}" ] && PSQL_VARS+=("-v" "n_posts=${N_POSTS}")
[ -n "${N_LIKES_TOTAL:-}" ] && PSQL_VARS+=("-v" "n_likes_total=${N_LIKES_TOTAL}")

docker exec -i "${CONTAINER_NAME}" psql -U postgres -d "${TEMPLATE_DB}" -v ON_ERROR_STOP=1 "${PSQL_VARS[@]}" < /home/diogo/Backend-k8s-Arena/db/seed.sql

# Vacuum and analyze for stable plans
echo "Running VACUUM (FREEZE, ANALYZE) and CHECKPOINT..."
docker exec "${CONTAINER_NAME}" psql -U postgres -d "${TEMPLATE_DB}" -c "VACUUM (FREEZE, ANALYZE); CHECKPOINT;"

SEED_END=$(date +%s)
echo "Seed completed in $((SEED_END - SEED_START)) seconds"