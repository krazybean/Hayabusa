#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
TLS_DIR="${ROOT_DIR}/secrets/windows-forward-tls"
OUTPUT_BASE_DIR="${ROOT_DIR}/dist/windows-endpoints"
ENDPOINT_ID=""
VECTOR_HOST=""
FORCE=false

usage() {
  cat <<'EOF'
Usage:
  ./scripts/enroll-windows-endpoint.sh --endpoint-id <id> --vector-host <host-or-ip> [options]

Options:
  --endpoint-id <id>      Endpoint identifier (used in cert CN and bundle path)
  --vector-host <value>   Reachable Hayabusa host/IP for Vector Windows lane (24225)
  --tls-dir <path>        TLS directory containing ca.crt + ca.key (default: secrets/windows-forward-tls)
  --output-dir <path>     Bundle output base dir (default: dist/windows-endpoints)
  --force                 Overwrite existing endpoint bundle directory
  -h, --help              Show this help
EOF
}

while [[ $# -gt 0 ]]; do
  case "$1" in
    --endpoint-id)
      ENDPOINT_ID="${2:-}"
      shift 2
      ;;
    --vector-host)
      VECTOR_HOST="${2:-}"
      shift 2
      ;;
    --tls-dir)
      TLS_DIR="${2:-}"
      shift 2
      ;;
    --output-dir)
      OUTPUT_BASE_DIR="${2:-}"
      shift 2
      ;;
    --force)
      FORCE=true
      shift
      ;;
    -h|--help)
      usage
      exit 0
      ;;
    *)
      echo "Unknown argument: $1" >&2
      usage
      exit 1
      ;;
  esac
done

if [[ -z "${ENDPOINT_ID}" || -z "${VECTOR_HOST}" ]]; then
  usage
  exit 1
fi

if [[ ! "${ENDPOINT_ID}" =~ ^[A-Za-z0-9._-]+$ ]]; then
  echo "ERROR: endpoint-id must match [A-Za-z0-9._-]+" >&2
  exit 1
fi

mkdir -p "${TLS_DIR}"
if [[ ! -f "${TLS_DIR}/ca.crt" || ! -f "${TLS_DIR}/ca.key" || ! -f "${TLS_DIR}/server.crt" || ! -f "${TLS_DIR}/server.key" ]]; then
  echo "INFO: base TLS assets missing in ${TLS_DIR}; generating them now."
  bash "${ROOT_DIR}/scripts/generate-windows-forward-certs.sh" "${TLS_DIR}"
fi

bundle_dir="${OUTPUT_BASE_DIR}/${ENDPOINT_ID}"
if [[ -e "${bundle_dir}" && "${FORCE}" != "true" ]]; then
  echo "ERROR: ${bundle_dir} already exists. Re-run with --force to overwrite." >&2
  exit 1
fi

rm -rf "${bundle_dir}"
mkdir -p "${bundle_dir}/certs"

tmpdir="$(mktemp -d)"
cleanup() {
  rm -rf "${tmpdir}"
}
trap cleanup EXIT

cat >"${tmpdir}/client.ext" <<'EOF'
basicConstraints=CA:FALSE
keyUsage=digitalSignature,keyEncipherment
extendedKeyUsage=clientAuth
EOF

client_key="${tmpdir}/${ENDPOINT_ID}.key"
client_csr="${tmpdir}/${ENDPOINT_ID}.csr"
client_crt="${tmpdir}/${ENDPOINT_ID}.crt"

openssl genrsa -out "${client_key}" 2048 >/dev/null 2>&1
openssl req -new \
  -key "${client_key}" \
  -subj "/CN=windows-endpoint-${ENDPOINT_ID}" \
  -out "${client_csr}" >/dev/null 2>&1
openssl x509 -req \
  -in "${client_csr}" \
  -CA "${TLS_DIR}/ca.crt" \
  -CAkey "${TLS_DIR}/ca.key" \
  -CAcreateserial \
  -days "${WINDOWS_TLS_DAYS:-825}" \
  -sha256 \
  -extfile "${tmpdir}/client.ext" \
  -out "${client_crt}" >/dev/null 2>&1

cp "${TLS_DIR}/ca.crt" "${bundle_dir}/certs/ca.crt"
cp "${client_crt}" "${bundle_dir}/certs/client.crt"
cp "${client_key}" "${bundle_dir}/certs/client.key"
chmod 600 "${bundle_dir}/certs/client.key"

awk -v host="${VECTOR_HOST}" '
  { gsub(/HAYABUSA_VECTOR_HOST/, host) }
  { print }
' "${ROOT_DIR}/configs/fluent-bit/windows/fluent-bit-windows-mtls.conf" > "${bundle_dir}/fluent-bit.conf"

cat > "${bundle_dir}/README.txt" <<EOF
Hayabusa Windows Endpoint Enrollment Bundle
Endpoint ID: ${ENDPOINT_ID}
Generated (UTC): $(date -u +"%Y-%m-%dT%H:%M:%SZ")

1) Install Fluent Bit on Windows endpoint.
2) Copy bundle contents:
   - fluent-bit.conf -> C:\\fluent-bit\\conf\\fluent-bit.conf
   - certs\\ca.crt    -> C:\\fluent-bit\\certs\\ca.crt
   - certs\\client.crt -> C:\\fluent-bit\\certs\\client.crt
   - certs\\client.key -> C:\\fluent-bit\\certs\\client.key
3) Start/Restart Fluent Bit service.
4) Validate from Hayabusa host:
   - ./scripts/windows-endpoint-check.sh
5) Register/verify endpoint policy entry:
   - configs/endpoints/windows-endpoints.yaml
   - ./scripts/endpoint-policy-drift-check.sh --only-id ${ENDPOINT_ID} --soft-fail

Vector target:
  ${VECTOR_HOST}:24225 (mTLS required)
EOF

echo "Created Windows endpoint enrollment bundle:"
echo "  ${bundle_dir}"
echo
echo "Bundle files:"
echo "  ${bundle_dir}/fluent-bit.conf"
echo "  ${bundle_dir}/certs/ca.crt"
echo "  ${bundle_dir}/certs/client.crt"
echo "  ${bundle_dir}/certs/client.key"
echo "  ${bundle_dir}/README.txt"
