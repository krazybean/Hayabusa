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

printf "[%s] Applying ClickHouse MVP migrations...\n" "$(timestamp)"
run_sql "ALTER TABLE security.events ADD COLUMN IF NOT EXISTS schema_version LowCardinality(String) DEFAULT 'hayabusa.event.v1' AFTER platform"
run_sql "CREATE TABLE IF NOT EXISTS security.alert_candidates (ts DateTime64(3, 'UTC') DEFAULT now64(3), rule_id String, rule_name String, severity LowCardinality(String), hits UInt64, threshold_op LowCardinality(String), threshold_value UInt64, query String, details String) ENGINE = MergeTree() PARTITION BY toYYYYMM(ts) ORDER BY (ts, rule_id) TTL ts + INTERVAL 30 DAY"
run_sql "CREATE OR REPLACE VIEW security.endpoint_activity AS SELECT endpoint_id, lane, first_seen, last_seen, total_events, dateDiff('minute', last_seen, now()) AS minutes_since_last_seen, multiIf(dateDiff('minute', last_seen, now()) <= 15, 'active', dateDiff('minute', last_seen, now()) <= 60, 'idle', 'stale') AS status FROM (SELECT coalesce(nullIf(fields['computer'], ''), nullIf(fields['hostname'], ''), nullIf(fields['host'], ''), 'unknown') AS endpoint_id, ingest_source AS lane, min(ts) AS first_seen, max(ts) AS last_seen, count() AS total_events FROM security.events GROUP BY endpoint_id, lane) WHERE endpoint_id != 'unknown'"

column_exists="$(query_scalar "SELECT count() FROM system.columns WHERE database = 'security' AND table = 'events' AND name = 'schema_version' FORMAT TabSeparated")"
if [[ "${column_exists}" != "1" ]]; then
  printf "[%s] ERROR: schema_version column missing after migration\n" "$(timestamp)" >&2
  exit 1
fi

alert_candidates_exists="$(query_scalar "SELECT count() FROM system.tables WHERE database = 'security' AND name = 'alert_candidates' FORMAT TabSeparated")"
if [[ "${alert_candidates_exists}" != "1" ]]; then
  printf "[%s] ERROR: alert_candidates table missing after migration\n" "$(timestamp)" >&2
  exit 1
fi

endpoint_activity_exists="$(query_scalar "SELECT count() FROM system.tables WHERE database = 'security' AND name = 'endpoint_activity' FORMAT TabSeparated")"
if [[ "${endpoint_activity_exists}" != "1" ]]; then
  printf "[%s] ERROR: endpoint_activity view missing after migration\n" "$(timestamp)" >&2
  exit 1
fi

printf "[%s] Migration complete: security.events.schema_version + security.alert_candidates + security.endpoint_activity ready\n" "$(timestamp)"
