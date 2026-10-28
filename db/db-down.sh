#!/usr/bin/env bash
# db-down: Stop and optionally remove Postgres container and volume
set -euo pipefail

REMOVE_VOLUME=false
for arg in "$@"; do
  case $arg in
    --volumes) REMOVE_VOLUME=true ;;
    *) echo "Unknown argument: $arg"; exit 1 ;;
  esac
done

CONTAINER_NAME="arena-postgres"
VOLUME_NAME="arena-pgdata"

if docker ps --format '{{.Names}}' | grep -q "^${CONTAINER_NAME}$"; then
  echo "Stopping container ${CONTAINER_NAME}..."
  docker stop "${CONTAINER_NAME}"
fi

if docker ps -a --format '{{.Names}}' | grep -q "^${CONTAINER_NAME}$"; then
  echo "Removing container ${CONTAINER_NAME}..."
  docker rm "${CONTAINER_NAME}"
fi

if [ "${REMOVE_VOLUME}" = true ]; then
  if docker volume ls --format '{{.Name}}' | grep -q "^${VOLUME_NAME}$"; then
    echo "Removing volume ${VOLUME_NAME}..."
    docker volume rm "${VOLUME_NAME}"
  fi
else
  echo "Volume ${VOLUME_NAME} preserved (use --volumes to remove)"
fi