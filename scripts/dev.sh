#!/usr/bin/env bash
set -euo pipefail

SERVICES=(
  clickhouse
  nats
  nats-init
  vector
  hayabusa-ingest
  api
  web
  detection
  alert-sink
  grafana
)

echo "Starting Hayabusa dev/demo services..."
docker compose up -d --build --remove-orphans "${SERVICES[@]}"

echo
echo "Watching logs for ingest, API, web, and detection."
echo "Press Ctrl+C to stop following logs. Use ./scripts/dev-down.sh when done."
echo

docker compose logs -f hayabusa-ingest api web detection
