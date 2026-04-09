#!/usr/bin/env bash
set -euo pipefail

echo "Starting Hayabusa strict MVP stack..."
docker compose up -d --remove-orphans

echo
echo "Current container status:"
docker compose ps

echo
echo "Endpoints:"
echo "  Grafana:      http://localhost:3000"
echo "  ClickHouse:   http://localhost:8123"
echo "  NATS monitor: http://localhost:8222"
echo "  Vector API:   http://localhost:8686"
echo "  Alert sink:   http://localhost:5678"
