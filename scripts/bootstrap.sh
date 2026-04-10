#!/usr/bin/env bash
set -euo pipefail

timestamp() {
  date +"%H:%M:%S"
}

log() {
  printf '[%s] %s\n' "$(timestamp)" "$*"
}

if ! command -v docker >/dev/null 2>&1; then
  echo "ERROR: docker is required." >&2
  exit 1
fi

if ! docker compose version >/dev/null 2>&1; then
  echo "ERROR: docker compose is required." >&2
  exit 1
fi

log "Starting Hayabusa demo stack..."
log "This starts ClickHouse, NATS, Vector, hayabusa-ingest, API, web UI, detection, Grafana, and alert-sink."
docker compose up -d --build --remove-orphans

echo
log "Current container status:"
docker compose ps

echo
log "Connection info:"
echo "  Demo UI:                  http://localhost:3000"
echo "  API:                      http://localhost:8080"
echo "  Grafana:                  http://localhost:3001"
echo "  ClickHouse HTTP:          http://localhost:8123"
echo "  NATS collector target:    nats://localhost:4222"
echo "  NATS monitor:             http://localhost:8222"
echo "  Vector API:               http://localhost:8686"
echo "  Alert sink:               http://localhost:5678"
echo
log "Next:"
echo "  1. Open http://localhost:3000"
echo "  2. Follow docs/windows-collector-quickstart.md from a Windows host"
echo "  3. Run ./scripts/smoke-test.sh for local validation"
