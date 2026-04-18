#!/bin/sh

set -eu

SCRIPT_DIR=$(CDPATH= cd -- "$(dirname "$0")" && pwd)
PROJECT_DIR=$(CDPATH= cd -- "${SCRIPT_DIR}/.." && pwd)

if [ "${1:-}" = "" ]; then
  echo "Usage: $0 <domain>" >&2
  exit 1
fi

DOMAIN="$1"

case "${DOMAIN}" in
  *[!A-Za-z0-9.-]*|'')
    echo "ERROR: invalid domain '${DOMAIN}'" >&2
    exit 1
    ;;
esac

if [ -f "${PROJECT_DIR}/.env" ]; then
  set -a
  # shellcheck disable=SC1091
  . "${PROJECT_DIR}/.env"
  set +a
fi

: "${GATEWAY_NETWORK:=gateway-net}"
: "${CERTBOT_IMAGE:=certbot/certbot}"

if [ "${CERTBOT_EMAIL:-}" = "" ]; then
  echo "ERROR: CERTBOT_EMAIL is not set. Add it to ${PROJECT_DIR}/.env" >&2
  exit 1
fi

mkdir -p \
  "${PROJECT_DIR}/certbot/www" \
  "${PROJECT_DIR}/certbot/conf"

if ! docker network inspect "${GATEWAY_NETWORK}" >/dev/null 2>&1; then
  echo "Creating Docker network '${GATEWAY_NETWORK}'"
  docker network create "${GATEWAY_NETWORK}" >/dev/null
fi

echo "Ensuring gateway container is running"
docker compose -f "${PROJECT_DIR}/compose.yaml" --project-directory "${PROJECT_DIR}" up -d gateway

CERT_PATH="${PROJECT_DIR}/certbot/conf/live/${DOMAIN}/fullchain.pem"
CERT_EXISTED=0

if [ -f "${CERT_PATH}" ]; then
  CERT_EXISTED=1
fi

echo "Requesting certificate for ${DOMAIN}"
docker run --rm \
  -v "${PROJECT_DIR}/certbot/www:/var/www/certbot" \
  -v "${PROJECT_DIR}/certbot/conf:/etc/letsencrypt" \
  "${CERTBOT_IMAGE}" certonly \
  --non-interactive \
  --agree-tos \
  --email "${CERTBOT_EMAIL}" \
  --webroot \
  --webroot-path /var/www/certbot \
  --cert-name "${DOMAIN}" \
  -d "${DOMAIN}" \
  --keep-until-expiring

if [ ! -f "${CERT_PATH}" ]; then
  echo "ERROR: certificate was not created for ${DOMAIN}" >&2
  exit 1
fi

if [ "${CERT_EXISTED}" -eq 1 ]; then
  echo "Reloading Nginx in gateway"
  docker exec gateway nginx -s reload
else
  echo "Restarting gateway to switch from fallback cert to Let's Encrypt cert"
  docker compose -f "${PROJECT_DIR}/compose.yaml" --project-directory "${PROJECT_DIR}" restart gateway
fi
