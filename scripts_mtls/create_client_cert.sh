#!/bin/sh

set -eu

SCRIPT_DIR=$(CDPATH= cd -- "$(dirname "$0")" && pwd)
PROJECT_DIR=$(CDPATH= cd -- "${SCRIPT_DIR}/.." && pwd)
OUTPUT_DIR=${1:-"${PROJECT_DIR}/secrets/client-ca"}
CLIENT_NAME=${2:-iphone}
CLIENT_DAYS=${CLIENT_DAYS:-3650}
CLIENT_COUNTRY=${CLIENT_COUNTRY:-RU}
CLIENT_STATE=${CLIENT_STATE:-Moscow}
CLIENT_CITY=${CLIENT_CITY:-Moscow}
CLIENT_ORG=${CLIENT_ORG:-Appline}
CLIENT_ORG_UNIT=${CLIENT_ORG_UNIT:-Clients}
CLIENT_COMMON_NAME=${CLIENT_COMMON_NAME:-${CLIENT_NAME}}

CA_KEY="${OUTPUT_DIR}/ca.key"
CA_CERT="${OUTPUT_DIR}/ca.crt"
CLIENT_KEY="${OUTPUT_DIR}/${CLIENT_NAME}.key"
CLIENT_CSR="${OUTPUT_DIR}/${CLIENT_NAME}.csr"
CLIENT_CERT="${OUTPUT_DIR}/${CLIENT_NAME}.crt"
CLIENT_EXT="${OUTPUT_DIR}/${CLIENT_NAME}.ext"

if [ ! -f "${CA_KEY}" ] || [ ! -f "${CA_CERT}" ]; then
  echo "ERROR: CA files not found in ${OUTPUT_DIR}" >&2
  echo "Run ./scripts/create_client_ca.sh first." >&2
  exit 1
fi

if [ -f "${CLIENT_KEY}" ] || [ -f "${CLIENT_CSR}" ] || [ -f "${CLIENT_CERT}" ]; then
  echo "ERROR: Client files for '${CLIENT_NAME}' already exist in ${OUTPUT_DIR}" >&2
  echo "Refusing to overwrite ${CLIENT_KEY}, ${CLIENT_CSR}, or ${CLIENT_CERT}" >&2
  exit 1
fi

SUBJECT="/C=${CLIENT_COUNTRY}/ST=${CLIENT_STATE}/L=${CLIENT_CITY}/O=${CLIENT_ORG}/OU=${CLIENT_ORG_UNIT}/CN=${CLIENT_COMMON_NAME}"

cat > "${CLIENT_EXT}" <<EOF
basicConstraints=CA:FALSE
keyUsage=digitalSignature,keyEncipherment
extendedKeyUsage=clientAuth
subjectKeyIdentifier=hash
authorityKeyIdentifier=keyid,issuer
EOF

echo "Generating client private key: ${CLIENT_KEY}"
openssl genrsa -out "${CLIENT_KEY}" 2048

echo "Generating CSR: ${CLIENT_CSR}"
openssl req -new -key "${CLIENT_KEY}" -out "${CLIENT_CSR}" -subj "${SUBJECT}"

echo "Signing client certificate: ${CLIENT_CERT}"
openssl x509 -req -in "${CLIENT_CSR}" -CA "${CA_CERT}" -CAkey "${CA_KEY}" -CAcreateserial \
  -out "${CLIENT_CERT}" -days "${CLIENT_DAYS}" -sha256 -extfile "${CLIENT_EXT}"

echo "Done."
echo "Client certificate: ${CLIENT_CERT}"
echo "Client private key: ${CLIENT_KEY}"
echo "Extension file: ${CLIENT_EXT}"
