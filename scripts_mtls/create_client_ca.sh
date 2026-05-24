#!/bin/sh

set -eu

SCRIPT_DIR=$(CDPATH= cd -- "$(dirname "$0")" && pwd)
PROJECT_DIR=$(CDPATH= cd -- "${SCRIPT_DIR}/.." && pwd)
OUTPUT_DIR=${1:-"${PROJECT_DIR}/secrets/client-ca"}
CA_DAYS=${CA_DAYS:-3650}
CA_COUNTRY=${CA_COUNTRY:-RU}
CA_STATE=${CA_STATE:-Moscow}
CA_CITY=${CA_CITY:-Moscow}
CA_ORG=${CA_ORG:-Appline}
CA_ORG_UNIT=${CA_ORG_UNIT:-Client CA}
CA_COMMON_NAME=${CA_COMMON_NAME:-Appline iPhone Client CA}

mkdir -p "${OUTPUT_DIR}"

CA_KEY="${OUTPUT_DIR}/ca.key"
CA_CERT="${OUTPUT_DIR}/ca.crt"

if [ -f "${CA_KEY}" ] || [ -f "${CA_CERT}" ]; then
  echo "ERROR: CA files already exist in ${OUTPUT_DIR}" >&2
  echo "Refusing to overwrite ${CA_KEY} or ${CA_CERT}" >&2
  exit 1
fi

SUBJECT="/C=${CA_COUNTRY}/ST=${CA_STATE}/L=${CA_CITY}/O=${CA_ORG}/OU=${CA_ORG_UNIT}/CN=${CA_COMMON_NAME}"

echo "Generating CA private key: ${CA_KEY}"
openssl genrsa -out "${CA_KEY}" 4096

echo "Generating CA certificate: ${CA_CERT}"
openssl req -x509 -new -nodes -key "${CA_KEY}" -sha256 -days "${CA_DAYS}" \
  -out "${CA_CERT}" \
  -subj "${SUBJECT}"

echo "Done."
echo "CA certificate: ${CA_CERT}"
echo "CA private key: ${CA_KEY}"
