#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "${ROOT_DIR}"

TIMEOUT_SECONDS="${SMOKE_TIMEOUT_SECONDS:-120}"
MAX_EVENTS_BYTES="${SMOKE_MAX_EVENTS_BYTES:-1073741824}"
NATS_STREAM_NAME="${SMOKE_NATS_STREAM_NAME:-HAYABUSA_EVENTS}"
NATS_CONSUMER_NAME="${SMOKE_NATS_CONSUMER_NAME:-VECTOR_CLICKHOUSE_WRITER}"
NATS_STREAM_SUBJECT_GLOB="${SMOKE_NATS_STREAM_SUBJECT_GLOB:-hayabusa.events.>}"
NATS_URL="${SMOKE_NATS_URL:-nats://nats:4222}"
FLUENT_INGEST_SOURCE="${SMOKE_FLUENT_INGEST_SOURCE:-vector-fluent}"
FLUENT_HOST_LOG_FILE="${SMOKE_FLUENT_HOST_LOG_FILE:-${ROOT_DIR}/data/host-logs/linux-auth.log}"
WINDOWS_INGEST_SOURCE="${SMOKE_WINDOWS_INGEST_SOURCE:-vector-windows-endpoint}"
WINDOWS_SIM_LOG_FILE="${SMOKE_WINDOWS_SIM_LOG_FILE:-${ROOT_DIR}/data/host-logs/windows-events.log}"
SKIP_WINDOWS_LANE_CHECK="${SMOKE_SKIP_WINDOWS_LANE_CHECK:-false}"
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

run_nats_cli() {
  docker compose run --rm --no-deps nats-init \
    nats --server "${NATS_URL}" "$@"
}

wait_for_nats() {
  local elapsed=0
  printf "[%s] Waiting for NATS JetStream CLI checks\n" "$(timestamp)"

  while (( elapsed < TIMEOUT_SECONDS )); do
    if run_nats_cli account info >/dev/null 2>&1; then
      printf "[%s] OK: NATS JetStream CLI reachable\n" "$(timestamp)"
      return 0
    fi
    sleep "${SLEEP_SECONDS}"
    elapsed=$((elapsed + SLEEP_SECONDS))
  done

  printf "[%s] ERROR: NATS JetStream did not become ready within %ss\n" "$(timestamp)" "${TIMEOUT_SECONDS}" >&2
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

query_ingest_source_count() {
  local ingest_source="$1"
  curl -fsS "http://localhost:8123/" \
    --data-binary "SELECT count() FROM security.events WHERE ingest_source = '${ingest_source}' FORMAT TabSeparated" | tr -d '\r\n'
}

query_nats_stream_info() {
  run_nats_cli stream info "${NATS_STREAM_NAME}"
}

echo "Running Hayabusa component smoke test..."
docker compose ps

wait_for_http "ClickHouse" "http://localhost:8123/ping" "ok"
wait_for_keeper
wait_for_nats
wait_for_http "Vector API" "http://localhost:8686/health"
wait_for_http "Prometheus" "http://localhost:9090/-/healthy" "healthy"
wait_for_http "Grafana" "http://localhost:3000/api/health" "\"database\"[[:space:]]*:[[:space:]]*\"ok\""
wait_for_detection

echo "Validating transport path (Vector -> NATS JetStream -> ClickHouse)..."
nats_stream_info="$(query_nats_stream_info)"
if grep -q "Stream ${NATS_STREAM_NAME}" <<<"${nats_stream_info}"; then
  printf "[%s] OK: JetStream stream present (%s)\n" "$(timestamp)" "${NATS_STREAM_NAME}"
else
  printf "[%s] ERROR: JetStream stream missing (%s)\n" "$(timestamp)" "${NATS_STREAM_NAME}" >&2
  exit 1
fi

nats_consumer_info="$(run_nats_cli consumer info "${NATS_STREAM_NAME}" "${NATS_CONSUMER_NAME}")"
if grep -q "Name: ${NATS_CONSUMER_NAME}" <<<"${nats_consumer_info}"; then
  printf "[%s] OK: JetStream consumer present (%s)\n" "$(timestamp)" "${NATS_CONSUMER_NAME}"
else
  printf "[%s] ERROR: JetStream consumer missing (%s)\n" "$(timestamp)" "${NATS_CONSUMER_NAME}" >&2
  exit 1
fi

if grep -Fq "Subjects: ${NATS_STREAM_SUBJECT_GLOB}" <<<"${nats_stream_info}"; then
  printf "[%s] OK: JetStream stream subject configured (%s)\n" "$(timestamp)" "${NATS_STREAM_SUBJECT_GLOB}"
else
  printf "[%s] ERROR: JetStream stream subject not found (%s)\n" "$(timestamp)" "${NATS_STREAM_SUBJECT_GLOB}" >&2
  exit 1
fi

if docker compose ps --services --status running | grep -q '^fluent-bit$'; then
  fluent_before="$(query_ingest_source_count "${FLUENT_INGEST_SOURCE}")"
  ./scripts/generate-host-logs.sh "${FLUENT_HOST_LOG_FILE}" >/dev/null
  sleep 3
  fluent_after="$(query_ingest_source_count "${FLUENT_INGEST_SOURCE}")"

  if [[ "${fluent_after}" =~ ^[0-9]+$ ]] && [[ "${fluent_before}" =~ ^[0-9]+$ ]] && (( fluent_after > fluent_before )); then
    printf "[%s] OK: Fluent Bit host log flow increased %s events (%s -> %s)\n" "$(timestamp)" "${FLUENT_INGEST_SOURCE}" "${fluent_before}" "${fluent_after}"
  else
    printf "[%s] ERROR: Fluent Bit host log flow did not increase %s events (%s -> %s)\n" "$(timestamp)" "${FLUENT_INGEST_SOURCE}" "${fluent_before}" "${fluent_after}" >&2
    exit 1
  fi

  if [[ "${SKIP_WINDOWS_LANE_CHECK}" == "true" ]]; then
    printf "[%s] INFO: skipping Windows lane flow check (SMOKE_SKIP_WINDOWS_LANE_CHECK=true)\n" "$(timestamp)"
  else
    windows_before="$(query_ingest_source_count "${WINDOWS_INGEST_SOURCE}")"
    ./scripts/generate-windows-events.sh "${WINDOWS_SIM_LOG_FILE}" >/dev/null
    sleep 3
    windows_after="$(query_ingest_source_count "${WINDOWS_INGEST_SOURCE}")"

    if [[ "${windows_after}" =~ ^[0-9]+$ ]] && [[ "${windows_before}" =~ ^[0-9]+$ ]] && (( windows_after > windows_before )); then
      printf "[%s] OK: Windows endpoint lane increased %s events (%s -> %s)\n" "$(timestamp)" "${WINDOWS_INGEST_SOURCE}" "${windows_before}" "${windows_after}"
    else
      printf "[%s] ERROR: Windows endpoint lane did not increase %s events (%s -> %s)\n" "$(timestamp)" "${WINDOWS_INGEST_SOURCE}" "${windows_before}" "${windows_after}" >&2
      exit 1
    fi
  fi
else
  printf "[%s] INFO: fluent-bit service not running; skipping collector path check\n" "$(timestamp)"
fi

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
