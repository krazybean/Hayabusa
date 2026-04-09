#!/usr/bin/env bash
set -euo pipefail

echo "Bringing up Hayabusa dev stack..."
docker compose up -d --remove-orphans

echo
echo "Current container status:"
docker compose ps
