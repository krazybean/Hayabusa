#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
TLS_DIR="${ROOT_DIR}/secrets/windows-forward-tls"

if [[ ! -f "${TLS_DIR}/ca.crt" || ! -f "${TLS_DIR}/server.crt" || ! -f "${TLS_DIR}/server.key" || ! -f "${TLS_DIR}/client.crt" || ! -f "${TLS_DIR}/client.key" ]]; then
  echo "Generating Windows forward mTLS certs in ${TLS_DIR}..."
  bash "${ROOT_DIR}/scripts/generate-windows-forward-certs.sh" "${TLS_DIR}"
fi

echo "Starting local security platform starter stack..."
docker compose up -d

echo
echo "Current container status:"
docker compose ps

echo
echo "Endpoints:"
echo "  Grafana:      http://localhost:3000"
echo "  Prometheus:   http://localhost:9090"
echo "  ClickHouse:   http://localhost:8123"
echo "  NATS monitor: http://localhost:8222"
echo "  Vector API:   http://localhost:8686"
