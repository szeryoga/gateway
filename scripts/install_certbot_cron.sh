#!/bin/sh

set -eu

SCRIPT_DIR=$(CDPATH= cd -- "$(dirname "$0")" && pwd)
PROJECT_DIR=$(CDPATH= cd -- "${SCRIPT_DIR}/.." && pwd)
CRON_SCHEDULE="${CRON_SCHEDULE:-0 3,15 * * *}"
ROUTES_FILE="${PROJECT_DIR}/config/routes.yml"
START_MARKER="# BEGIN gateway-certbot-renew"
END_MARKER="# END gateway-certbot-renew"
MODE="install"
DRY_RUN=0

usage() {
  cat >&2 <<EOF
Usage:
  $0 [--schedule "<cron>"] [--routes-file <path>] [--dry-run]
  $0 --remove
EOF
}

build_cron_block() {
  command="/bin/sh -lc 'cd ${PROJECT_DIR} && ./scripts/renew_all_certs.sh"

  if [ "${ROUTES_FILE}" != "${PROJECT_DIR}/config/routes.yml" ]; then
    command="${command} --routes-file ${ROUTES_FILE}"
  fi

  command="${command}'"

  printf '%s\n' \
    "${START_MARKER}" \
    "${CRON_SCHEDULE} ${command}" \
    "${END_MARKER}"
}

get_current_crontab() {
  if crontab -l >/dev/null 2>&1; then
    crontab -l
  fi
}

strip_managed_block() {
  awk -v start="${START_MARKER}" -v end="${END_MARKER}" '
    $0 == start {skip=1; next}
    $0 == end {skip=0; next}
    skip != 1 {print}
  '
}

while [ "$#" -gt 0 ]; do
  case "$1" in
    --schedule)
      if [ "${2:-}" = "" ]; then
        usage
        exit 1
      fi
      CRON_SCHEDULE="$2"
      shift 2
      ;;
    --routes-file)
      if [ "${2:-}" = "" ]; then
        usage
        exit 1
      fi
      ROUTES_FILE="$2"
      shift 2
      ;;
    --dry-run)
      DRY_RUN=1
      shift
      ;;
    --remove)
      MODE="remove"
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

CURRENT_CRONTAB=$(get_current_crontab)
CLEAN_CRONTAB=$(printf '%s\n' "${CURRENT_CRONTAB}" | strip_managed_block)

if [ "${MODE}" = "remove" ]; then
  if [ "${DRY_RUN}" -eq 1 ]; then
    printf '%s\n' "${CLEAN_CRONTAB}"
    exit 0
  fi

  printf '%s\n' "${CLEAN_CRONTAB}" | crontab -
  echo "Removed managed gateway certificate renewal cron entry"
  exit 0
fi

if [ ! -f "${ROUTES_FILE}" ]; then
  echo "ERROR: routes file not found: ${ROUTES_FILE}" >&2
  exit 1
fi

MANAGED_BLOCK=$(build_cron_block)
NEW_CRONTAB="${CLEAN_CRONTAB}"

if [ -n "${NEW_CRONTAB}" ]; then
  NEW_CRONTAB="${NEW_CRONTAB}
${MANAGED_BLOCK}"
else
  NEW_CRONTAB="${MANAGED_BLOCK}"
fi

if [ "${DRY_RUN}" -eq 1 ]; then
  printf '%s\n' "${NEW_CRONTAB}"
  exit 0
fi

printf '%s\n' "${NEW_CRONTAB}" | crontab -
echo "Installed managed gateway certificate renewal cron entry"
