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

if docker compose version >/dev/null 2>&1; then
  compose() {
    docker compose "$@"
  }
elif command -v docker-compose >/dev/null 2>&1; then
  compose() {
    docker-compose "$@"
  }
else
  echo "ERROR: Docker Compose is not available. Install 'docker compose' or 'docker-compose'." >&2
  exit 1
fi

if ! docker network inspect "${GATEWAY_NETWORK}" >/dev/null 2>&1; then
  echo "Creating Docker network '${GATEWAY_NETWORK}'"
  docker network create "${GATEWAY_NETWORK}" >/dev/null
fi

echo "Starting gateway containers"
compose -f "${PROJECT_DIR}/compose.yaml" --project-directory "${PROJECT_DIR}" up -d --build
