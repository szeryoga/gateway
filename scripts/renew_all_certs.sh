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

ROUTES_FILE="${GATEWAY_ROUTES_FILE:-${PROJECT_DIR}/config/routes.yml}"
LIST_ONLY=0

usage() {
  echo "Usage: $0 [--routes-file <path>] [--list-domains]" >&2
}

extract_domains() {
  awk '
    /^[[:space:]]*-[[:space:]]*host:[[:space:]]*/ {
      print $3
    }
    /^[[:space:]]*host:[[:space:]]*/ {
      print $2
    }
  ' "$1"
}

while [ "$#" -gt 0 ]; do
  case "$1" in
    --routes-file)
      if [ "${2:-}" = "" ]; then
        usage
        exit 1
      fi
      ROUTES_FILE="$2"
      shift 2
      ;;
    --list-domains)
      LIST_ONLY=1
      shift
      ;;
    -h|--help)
      usage
      exit 0
      ;;
    *)
      usage
      exit 1
      ;;
  esac
done

if [ ! -f "${ROUTES_FILE}" ]; then
  echo "ERROR: routes file not found: ${ROUTES_FILE}" >&2
  exit 1
fi

DOMAINS=$(extract_domains "${ROUTES_FILE}" | awk 'NF {print $0}' | sort -u)

if [ "${DOMAINS}" = "" ]; then
  echo "ERROR: no domains found in ${ROUTES_FILE}" >&2
  exit 1
fi

if [ "${LIST_ONLY}" -eq 1 ]; then
  printf '%s\n' "${DOMAINS}"
  exit 0
fi

echo "Renewing certificates from ${ROUTES_FILE}"

printf '%s\n' "${DOMAINS}" | while IFS= read -r domain; do
  echo "Processing ${domain}"
  "${SCRIPT_DIR}/certbot.sh" "${domain}"
done
