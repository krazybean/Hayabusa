#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
OUT_DIR="${1:-${ROOT_DIR}/secrets/windows-forward-tls}"
DAYS="${WINDOWS_TLS_DAYS:-825}"
FORCE="${WINDOWS_TLS_FORCE:-false}"

if [[ "${FORCE}" != "true" ]] && [[ -f "${OUT_DIR}/ca.crt" || -f "${OUT_DIR}/server.crt" || -f "${OUT_DIR}/client.crt" ]]; then
  echo "ERROR: TLS files already exist in ${OUT_DIR}. Set WINDOWS_TLS_FORCE=true to overwrite." >&2
  exit 1
fi

rm -rf "${OUT_DIR}"
mkdir -p "${OUT_DIR}"
# Keep placeholder for repo-tracked secrets directory.
: > "${OUT_DIR}/.gitkeep"

tmpdir="$(mktemp -d)"
cleanup() {
  rm -rf "${tmpdir}"
}
trap cleanup EXIT

cat >"${tmpdir}/server.ext" <<'EOF'
basicConstraints=CA:FALSE
keyUsage=digitalSignature,keyEncipherment
extendedKeyUsage=serverAuth
subjectAltName=DNS:vector,DNS:localhost,IP:127.0.0.1
EOF

cat >"${tmpdir}/client.ext" <<'EOF'
basicConstraints=CA:FALSE
keyUsage=digitalSignature,keyEncipherment
extendedKeyUsage=clientAuth
EOF

# Certificate authority
openssl genrsa -out "${OUT_DIR}/ca.key" 4096 >/dev/null 2>&1
openssl req -x509 -new -nodes \
  -key "${OUT_DIR}/ca.key" \
  -sha256 \
  -days "${DAYS}" \
  -subj "/CN=Hayabusa Windows Forward CA" \
  -out "${OUT_DIR}/ca.crt" >/dev/null 2>&1

# Vector server certificate
openssl genrsa -out "${OUT_DIR}/server.key" 2048 >/dev/null 2>&1
openssl req -new \
  -key "${OUT_DIR}/server.key" \
  -subj "/CN=vector" \
  -out "${tmpdir}/server.csr" >/dev/null 2>&1
openssl x509 -req \
  -in "${tmpdir}/server.csr" \
  -CA "${OUT_DIR}/ca.crt" \
  -CAkey "${OUT_DIR}/ca.key" \
  -CAcreateserial \
  -days "${DAYS}" \
  -sha256 \
  -extfile "${tmpdir}/server.ext" \
  -out "${OUT_DIR}/server.crt" >/dev/null 2>&1

# Windows client certificate
openssl genrsa -out "${OUT_DIR}/client.key" 2048 >/dev/null 2>&1
openssl req -new \
  -key "${OUT_DIR}/client.key" \
  -subj "/CN=windows-endpoint" \
  -out "${tmpdir}/client.csr" >/dev/null 2>&1
openssl x509 -req \
  -in "${tmpdir}/client.csr" \
  -CA "${OUT_DIR}/ca.crt" \
  -CAkey "${OUT_DIR}/ca.key" \
  -CAcreateserial \
  -days "${DAYS}" \
  -sha256 \
  -extfile "${tmpdir}/client.ext" \
  -out "${OUT_DIR}/client.crt" >/dev/null 2>&1

chmod 600 "${OUT_DIR}/ca.key" "${OUT_DIR}/server.key" "${OUT_DIR}/client.key"

cat <<EOF
Generated Windows forward mTLS assets in:
  ${OUT_DIR}

Files:
  ca.crt / ca.key
  server.crt / server.key
  client.crt / client.key

Next steps:
  1) Configure Vector Windows lane TLS with server certs (server.crt/server.key/ca.crt)
  2) Configure Windows Fluent Bit forward output TLS with client certs (client.crt/client.key/ca.crt)
  3) Restrict permit_origin in configs/vector/vector.yaml to your endpoint CIDRs
EOF
