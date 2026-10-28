#!/usr/bin/env bash
# db-reset: Recreate working database from template
set -euo pipefail

CONTAINER_NAME="arena-postgres"
TEMPLATE_DB="arena_template"
WORK_DB="arena"

if ! docker ps --format '{{.Names}}' | grep -q "^${CONTAINER_NAME}$"; then
  echo "ERROR: Container ${CONTAINER_NAME} not running. Run db-up first."
  exit 1
fi

RESET_START=$(date +%s)

echo "Terminating existing connections to ${WORK_DB}..."
docker exec "${CONTAINER_NAME}" psql -U postgres -d postgres -c "
  SELECT pg_terminate_backend(pid)
  FROM pg_stat_activity
  WHERE datname = '${WORK_DB}' AND pid <> pg_backend_pid();
" >/dev/null 2>&1 || true

echo "Dropping and recreating ${WORK_DB} from template..."
docker exec "${CONTAINER_NAME}" psql -U postgres -d postgres -c "
  DROP DATABASE IF EXISTS ${WORK_DB};
  CREATE DATABASE ${WORK_DB} TEMPLATE ${TEMPLATE_DB} STRATEGY = file_copy;
"

RESET_END=$(date +%s)
echo "Reset completed in $((RESET_END - RESET_START)) seconds"