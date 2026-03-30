#!/usr/bin/env bash
set -euo pipefail

CLICKHOUSE_URL="${CLICKHOUSE_URL:-http://localhost:8123}"
TIMEOUT_SECONDS="${MIGRATIONS_TIMEOUT_SECONDS:-120}"
SLEEP_SECONDS="${MIGRATIONS_SLEEP_SECONDS:-2}"

timestamp() {
  date +"%H:%M:%S"
}

wait_for_clickhouse() {
  local elapsed=0
  printf "[%s] Waiting for ClickHouse at %s/ping\n" "$(timestamp)" "${CLICKHOUSE_URL}"
  while (( elapsed < TIMEOUT_SECONDS )); do
    if curl -fsS "${CLICKHOUSE_URL}/ping" >/dev/null 2>&1; then
      printf "[%s] ClickHouse reachable\n" "$(timestamp)"
      return 0
    fi
    sleep "${SLEEP_SECONDS}"
    elapsed=$((elapsed + SLEEP_SECONDS))
  done
  printf "[%s] ERROR: ClickHouse not reachable after %ss\n" "$(timestamp)" "${TIMEOUT_SECONDS}" >&2
  return 1
}

run_sql() {
  local sql="$1"
  curl -fsS "${CLICKHOUSE_URL}/" --data-binary "${sql}" >/dev/null
}

query_scalar() {
  local sql="$1"
  curl -fsS "${CLICKHOUSE_URL}/" --data-binary "${sql}" | tr -d '\r\n'
}

wait_for_clickhouse

printf "[%s] Applying ClickHouse event schema migrations...\n" "$(timestamp)"
run_sql "ALTER TABLE security.events ADD COLUMN IF NOT EXISTS schema_version LowCardinality(String) DEFAULT 'hayabusa.event.v1' AFTER platform"

column_exists="$(query_scalar "SELECT count() FROM system.columns WHERE database = 'security' AND table = 'events' AND name = 'schema_version' FORMAT TabSeparated")"
if [[ "${column_exists}" != "1" ]]; then
  printf "[%s] ERROR: schema_version column missing after migration\n" "$(timestamp)" >&2
  exit 1
fi

printf "[%s] Migration complete: security.events.schema_version present\n" "$(timestamp)"
