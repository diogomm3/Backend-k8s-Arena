#!/usr/bin/env bash
# db-up: Start Postgres container and ensure template database exists
set -euo pipefail

# Configuration (overridable via env)
POSTGRES_IMAGE="${POSTGRES_IMAGE:-postgres:16.8-alpine@sha256:3b057e1c2c6dfee60a30950096f3fab33be141dbb0fdd7af3d477083de94166c}"
POSTGRES_PASSWORD="${POSTGRES_PASSWORD:-arena_local}"
CONTAINER_NAME="arena-postgres"
VOLUME_NAME="arena-pgdata"
PORT="5432"
TEMPLATE_DB="arena_template"

# Find current 16.x patch digest
# Verified via: docker pull postgres:16.8-alpine && docker inspect --format='{{.RepoDigests}}'
# As of 2026-10-27, postgres:16.8-alpine digest: sha256:3b057e1c2c6dfee60a30950096f3fab33be141dbb0fdd7af3d477083de94166c

# Check if container already running
if docker ps --format '{{.Names}}' | grep -q "^${CONTAINER_NAME}$"; then
  echo "Container ${CONTAINER_NAME} already running"
  exit 0
fi

# Check if container exists but stopped
if docker ps -a --format '{{.Names}}' | grep -q "^${CONTAINER_NAME}$"; then
  echo "Starting existing container ${CONTAINER_NAME}"
  docker start "${CONTAINER_NAME}"
else
  echo "Creating new container ${CONTAINER_NAME}"
  docker run -d \
    --name "${CONTAINER_NAME}" \
    -e POSTGRES_PASSWORD="${POSTGRES_PASSWORD}" \
    -e POSTGRES_DB="${TEMPLATE_DB}" \
    -e POSTGRES_INITDB_ARGS="--locale=C --encoding=UTF8" \
    -v "${VOLUME_NAME}:/var/lib/postgresql/data" \
    -p 127.0.0.1:${PORT}:5432 \
    --shm-size=256m \
    "${POSTGRES_IMAGE}" \
    -c shared_buffers=256MB \
    -c max_connections=200 \
    -c work_mem=4MB \
    -c maintenance_work_mem=64MB \
    -c effective_cache_size=768MB \
    -c random_page_cost=1.1
fi

# Wait for Postgres to be ready
echo "Waiting for Postgres to be ready..."
for i in {1..30}; do
  if docker exec "${CONTAINER_NAME}" pg_isready -U postgres -d "${TEMPLATE_DB}" >/dev/null 2>&1; then
    echo "Postgres is ready"
    break
  fi
  sleep 1
  if [ $i -eq 30 ]; then
    echo "ERROR: Postgres did not become ready in time"
    exit 1
  fi
done

# Check if template DB needs seeding
TABLE_COUNT=$(docker exec "${CONTAINER_NAME}" psql -U postgres -d "${TEMPLATE_DB}" -tAc "
  SELECT count(*) FROM information_schema.tables WHERE table_schema='public' AND table_name IN ('users','posts','likes')
" 2>/dev/null || echo 0)

if [ "${TABLE_COUNT}" -lt 3 ]; then
  echo "Template database not fully initialized, running seed..."
  /home/diogo/Backend-k8s-Arena/db/db-seed.sh --force
else
  echo "Template database already exists with schema"
fi