#!/usr/bin/env bash
set -euo pipefail

echo "Tearing down Hayabusa dev stack..."
docker compose down --remove-orphans

echo
echo "Current container status:"
docker compose ps --all
