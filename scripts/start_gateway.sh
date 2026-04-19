#!/bin/sh

set -eu

SCRIPT_DIR=$(CDPATH= cd -- "$(dirname "$0")" && pwd)
PROJECT_DIR=$(CDPATH= cd -- "${SCRIPT_DIR}/.." && pwd)

if [ -f "${PROJECT_DIR}/.env" ]; then
  set -a
  # shellcheck disable=SC1091
  . "${PROJECT_DIR}/.env"
  set +a
fi

: "${GATEWAY_NETWORK:=gateway-net}"

if ! docker network inspect "${GATEWAY_NETWORK}" >/dev/null 2>&1; then
  echo "Creating Docker network '${GATEWAY_NETWORK}'"
  docker network create "${GATEWAY_NETWORK}" >/dev/null
fi

echo "Starting gateway containers"
docker compose -f "${PROJECT_DIR}/compose.yaml" --project-directory "${PROJECT_DIR}" up -d --build
