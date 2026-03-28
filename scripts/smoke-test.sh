#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "${ROOT_DIR}"

TIMEOUT_SECONDS="${SMOKE_TIMEOUT_SECONDS:-120}"
MAX_EVENTS_BYTES="${SMOKE_MAX_EVENTS_BYTES:-1073741824}"
SLEEP_SECONDS=2

timestamp() {
  date +"%H:%M:%S"
}

wait_for_http() {
  local name="$1"
  local url="$2"
  local pattern="${3:-}"
  local elapsed=0

  printf "[%s] Waiting for %s at %s\n" "$(timestamp)" "${name}" "${url}"

  while (( elapsed < TIMEOUT_SECONDS )); do
    local body
    if body="$(curl -fsS "${url}" 2>/dev/null)"; then
      if [[ -z "${pattern}" ]] || grep -qi "${pattern}" <<<"${body}"; then
        printf "[%s] OK: %s\n" "$(timestamp)" "${name}"
        return 0
      fi
    fi
    sleep "${SLEEP_SECONDS}"
    elapsed=$((elapsed + SLEEP_SECONDS))
  done

  printf "[%s] ERROR: %s did not become ready within %ss\n" "$(timestamp)" "${name}" "${TIMEOUT_SECONDS}" >&2
  return 1
}

wait_for_keeper() {
  local elapsed=0
  printf "[%s] Waiting for ClickHouse Keeper client check\n" "$(timestamp)"

  while (( elapsed < TIMEOUT_SECONDS )); do
    if docker compose exec -T clickhouse-keeper \
      clickhouse-keeper-client --host localhost --port 9181 ls / >/dev/null 2>&1; then
      printf "[%s] OK: ClickHouse Keeper\n" "$(timestamp)"
      return 0
    fi
    sleep "${SLEEP_SECONDS}"
    elapsed=$((elapsed + SLEEP_SECONDS))
  done

  printf "[%s] ERROR: ClickHouse Keeper did not become ready within %ss\n" "$(timestamp)" "${TIMEOUT_SECONDS}" >&2
  return 1
}

wait_for_detection() {
  local elapsed=0
  printf "[%s] Waiting for detection heartbeat\n" "$(timestamp)"

  while (( elapsed < TIMEOUT_SECONDS )); do
    if docker compose exec -T detection sh -c "test -f /tmp/detection-heartbeat" >/dev/null 2>&1; then
      printf "[%s] OK: Detection service\n" "$(timestamp)"
      return 0
    fi
    sleep "${SLEEP_SECONDS}"
    elapsed=$((elapsed + SLEEP_SECONDS))
  done

  printf "[%s] ERROR: Detection service did not become ready within %ss\n" "$(timestamp)" "${TIMEOUT_SECONDS}" >&2
  return 1
}

query_clickhouse_count() {
  curl -fsS "http://localhost:8123/" \
    --data-binary "SELECT count() FROM security.events FORMAT TabSeparated" | tr -d '\r\n'
}

query_clickhouse_bytes() {
  curl -fsS "http://localhost:8123/" \
    --data-binary "SELECT toUInt64(ifNull(sum(bytes_on_disk), 0)) FROM system.parts WHERE active AND database = 'security' AND table = 'events' FORMAT TabSeparated" | tr -d '\r\n'
}

query_alert_candidates_table_exists() {
  curl -fsS "http://localhost:8123/" \
    --data-binary "SELECT count() FROM system.tables WHERE database = 'security' AND name = 'alert_candidates' FORMAT TabSeparated" | tr -d '\r\n'
}

echo "Running Hayabusa component smoke test..."
docker compose ps

wait_for_http "ClickHouse" "http://localhost:8123/ping" "ok"
wait_for_keeper
wait_for_http "NATS monitoring" "http://localhost:8222/healthz"
wait_for_http "Vector API" "http://localhost:8686/health"
wait_for_http "Prometheus" "http://localhost:9090/-/healthy" "healthy"
wait_for_http "Grafana" "http://localhost:3000/api/health" "\"database\"[[:space:]]*:[[:space:]]*\"ok\""
wait_for_detection

echo "Validating ingest path (Vector -> ClickHouse)..."
before_count="$(query_clickhouse_count)"
sleep 5
after_count="$(query_clickhouse_count)"

if [[ "${after_count}" =~ ^[0-9]+$ ]] && [[ "${before_count}" =~ ^[0-9]+$ ]] && (( after_count > before_count )); then
  printf "[%s] OK: security.events count increased (%s -> %s)\n" "$(timestamp)" "${before_count}" "${after_count}"
else
  printf "[%s] ERROR: security.events count did not increase (%s -> %s)\n" "$(timestamp)" "${before_count}" "${after_count}" >&2
  exit 1
fi

alert_candidates_table_exists="$(query_alert_candidates_table_exists)"
if [[ "${alert_candidates_table_exists}" == "1" ]]; then
  printf "[%s] OK: security.alert_candidates table exists\n" "$(timestamp)"
else
  printf "[%s] ERROR: security.alert_candidates table missing\n" "$(timestamp)" >&2
  exit 1
fi

events_bytes="$(query_clickhouse_bytes)"
if [[ "${events_bytes}" =~ ^[0-9]+$ ]] && (( events_bytes <= MAX_EVENTS_BYTES )); then
  printf "[%s] OK: security.events bytes within budget (%s <= %s)\n" "$(timestamp)" "${events_bytes}" "${MAX_EVENTS_BYTES}"
else
  printf "[%s] ERROR: security.events bytes over budget (%s > %s)\n" "$(timestamp)" "${events_bytes}" "${MAX_EVENTS_BYTES}" >&2
  exit 1
fi

echo "Smoke test passed."
