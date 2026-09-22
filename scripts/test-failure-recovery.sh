#!/usr/bin/env bash
set -euo pipefail

TIMEOUT_SECONDS="${FAILURE_TEST_TIMEOUT_SECONDS:-90}"
SLEEP_SECONDS=2

wait_for_pattern() {
  local name="$1"
  local url="$2"
  local pattern="$3"
  local elapsed=0
  while (( elapsed < TIMEOUT_SECONDS )); do
    local body
    if body="$(curl -fsS "${url}" 2>/dev/null)" && grep -q "${pattern}" <<<"${body}"; then
      echo "PASS: ${name}"
      return 0
    fi
    sleep "${SLEEP_SECONDS}"
    elapsed=$((elapsed + SLEEP_SECONDS))
  done
  echo "ERROR: ${name} did not reach expected state" >&2
  return 1
}

wait_for_clickhouse() {
  local elapsed=0
  while (( elapsed < TIMEOUT_SECONDS )); do
    if curl -fsS http://localhost:8123/ping 2>/dev/null | grep -qi ok; then
      return 0
    fi
    sleep "${SLEEP_SECONDS}"
    elapsed=$((elapsed + SLEEP_SECONDS))
  done
  echo "ERROR: ClickHouse did not recover" >&2
  return 1
}

query_count() {
  curl -fsS http://localhost:8123/ --data-binary "SELECT count() FROM security.events FORMAT TabSeparated" | tr -d '\r\n'
}

echo "Testing ClickHouse outage visibility and recovery..."
docker compose stop clickhouse >/dev/null
wait_for_pattern "API reports ClickHouse unavailable" "http://localhost:8080/health" '"clickhouse_connected":false'
docker compose start clickhouse >/dev/null
wait_for_clickhouse
wait_for_pattern "API reports ClickHouse recovered" "http://localhost:8080/health" '"clickhouse_connected":true'

echo "Testing NATS outage visibility and recovery..."
docker compose stop nats >/dev/null
wait_for_pattern "API reports NATS unavailable" "http://localhost:8080/health" '"nats_connected":false'
docker compose start nats >/dev/null
wait_for_pattern "API reports NATS recovered" "http://localhost:8080/health" '"nats_connected":true'

echo "Testing post-recovery event flow..."
before="$(query_count)"
curl -fsS -X POST http://localhost:8080/generate-test-event >/dev/null
elapsed=0
after="${before}"
while (( elapsed < TIMEOUT_SECONDS )); do
  after="$(query_count)"
  if [[ "${before}" =~ ^[0-9]+$ ]] && [[ "${after}" =~ ^[0-9]+$ ]] && (( after > before )); then
    echo "PASS: event flow recovered (${before} -> ${after})"
    echo "Failure/recovery tests passed."
    exit 0
  fi
  sleep "${SLEEP_SECONDS}"
  elapsed=$((elapsed + SLEEP_SECONDS))
done

echo "ERROR: event flow did not recover after dependency restart (${before} -> ${after})" >&2
docker compose logs --tail=100 hayabusa-ingest detection api >&2 || true
exit 1
