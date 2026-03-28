#!/usr/bin/env bash
set -euo pipefail

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
