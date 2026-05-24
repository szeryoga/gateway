#!/bin/sh

set -eu

SCRIPT_DIR=$(CDPATH= cd -- "$(dirname "$0")" && pwd)
PROJECT_DIR=$(CDPATH= cd -- "${SCRIPT_DIR}/.." && pwd)
OUTPUT_DIR=${1:-"${PROJECT_DIR}/secrets/client-ca"}
CLIENT_NAME=${2:-iphone}
P12_NAME=${P12_NAME:-iphone}
P12_LABEL=${P12_LABEL:-Appline iPhone Client}

CA_CERT="${OUTPUT_DIR}/ca.crt"
CLIENT_KEY="${OUTPUT_DIR}/${CLIENT_NAME}.key"
CLIENT_CERT="${OUTPUT_DIR}/${CLIENT_NAME}.crt"
P12_PATH="${OUTPUT_DIR}/${P12_NAME}.p12"

if [ ! -f "${CA_CERT}" ] || [ ! -f "${CLIENT_KEY}" ] || [ ! -f "${CLIENT_CERT}" ]; then
  echo "ERROR: Required files are missing in ${OUTPUT_DIR}" >&2
  echo "Need ${CA_CERT}, ${CLIENT_KEY}, and ${CLIENT_CERT}" >&2
  echo "Run ./scripts/create_client_ca.sh and ./scripts/create_client_cert.sh first." >&2
  exit 1
fi

if [ -f "${P12_PATH}" ]; then
  echo "ERROR: ${P12_PATH} already exists" >&2
  echo "Refusing to overwrite existing .p12 file" >&2
  exit 1
fi

echo "Exporting PKCS#12 bundle: ${P12_PATH}"
echo "OpenSSL will ask for an export password. iPhone will request this password during import."
openssl pkcs12 -export \
  -out "${P12_PATH}" \
  -inkey "${CLIENT_KEY}" \
  -in "${CLIENT_CERT}" \
  -certfile "${CA_CERT}" \
  -name "${P12_LABEL}"

echo "Done."
echo "PKCS#12 bundle: ${P12_PATH}"
