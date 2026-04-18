#!/bin/sh

set -eu

FALLBACK_CERT_DIR="/etc/nginx/fallback"
FALLBACK_KEY="${FALLBACK_CERT_DIR}/default.key"
FALLBACK_CERT="${FALLBACK_CERT_DIR}/default.crt"

mkdir -p "${FALLBACK_CERT_DIR}" /var/www/certbot /etc/nginx/generated

if [ ! -f "${FALLBACK_CERT}" ] || [ ! -f "${FALLBACK_KEY}" ]; then
  openssl req -x509 -nodes -newkey rsa:2048 \
    -keyout "${FALLBACK_KEY}" \
    -out "${FALLBACK_CERT}" \
    -days 3650 \
    -subj "/CN=gateway-default"
fi

python3 /app/scripts/generate_nginx_conf.py \
  --routes /app/config/routes.yml \
  --template /app/nginx/nginx.conf.template \
  --output /etc/nginx/nginx.conf

nginx -t

exec nginx -g "daemon off;"
