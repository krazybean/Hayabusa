#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT_DIR="$(cd "${SCRIPT_DIR}/.." && pwd)"
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

run_sql_file() {
  local file="$1"
  curl -fsS "${CLICKHOUSE_URL}/" --data-binary @"${file}" >/dev/null
}

query_scalar() {
  local sql="$1"
  curl -fsS "${CLICKHOUSE_URL}/" --data-binary "${sql}" | tr -d '\r\n'
}

wait_for_clickhouse

printf "[%s] Applying ClickHouse MVP migrations...\n" "$(timestamp)"
run_sql "ALTER TABLE security.events ADD COLUMN IF NOT EXISTS schema_version LowCardinality(String) DEFAULT 'hayabusa.event.v1' AFTER platform"
run_sql_file "${ROOT_DIR}/configs/clickhouse/initdb/02_create_alert_candidates_table.sql"
run_sql "ALTER TABLE security.alert_candidates ADD COLUMN IF NOT EXISTS principal String DEFAULT '' AFTER hits"
run_sql "ALTER TABLE security.alert_candidates ADD COLUMN IF NOT EXISTS alert_type LowCardinality(String) DEFAULT '' AFTER rule_name"
run_sql "ALTER TABLE security.alert_candidates ADD COLUMN IF NOT EXISTS alert_fingerprint String DEFAULT '' AFTER alert_type"
run_sql "ALTER TABLE security.alert_candidates ADD COLUMN IF NOT EXISTS attempt_count UInt64 DEFAULT 0 AFTER hits"
run_sql "ALTER TABLE security.alert_candidates ADD COLUMN IF NOT EXISTS entity_user String DEFAULT '' AFTER principal"
run_sql "ALTER TABLE security.alert_candidates ADD COLUMN IF NOT EXISTS source_ip String DEFAULT '' AFTER principal"
run_sql "ALTER TABLE security.alert_candidates ADD COLUMN IF NOT EXISTS entity_src_ip String DEFAULT '' AFTER source_ip"
run_sql "ALTER TABLE security.alert_candidates ADD COLUMN IF NOT EXISTS endpoint_id String DEFAULT '' AFTER source_ip"
run_sql "ALTER TABLE security.alert_candidates ADD COLUMN IF NOT EXISTS entity_host String DEFAULT '' AFTER endpoint_id"
run_sql "ALTER TABLE security.alert_candidates ADD COLUMN IF NOT EXISTS window_start DateTime64(3, 'UTC') DEFAULT now64(3) AFTER endpoint_id"
run_sql "ALTER TABLE security.alert_candidates ADD COLUMN IF NOT EXISTS first_seen_ts DateTime64(3, 'UTC') DEFAULT now64(3) AFTER window_start"
run_sql "ALTER TABLE security.alert_candidates ADD COLUMN IF NOT EXISTS window_end DateTime64(3, 'UTC') DEFAULT now64(3) AFTER window_start"
run_sql "ALTER TABLE security.alert_candidates ADD COLUMN IF NOT EXISTS last_seen_ts DateTime64(3, 'UTC') DEFAULT now64(3) AFTER window_end"
run_sql "ALTER TABLE security.alert_candidates ADD COLUMN IF NOT EXISTS window_bucket DateTime64(3, 'UTC') DEFAULT now64(3) AFTER last_seen_ts"
run_sql "ALTER TABLE security.alert_candidates ADD COLUMN IF NOT EXISTS distinct_user_count UInt64 DEFAULT 0 AFTER window_bucket"
run_sql "ALTER TABLE security.alert_candidates ADD COLUMN IF NOT EXISTS distinct_ip_count UInt64 DEFAULT 0 AFTER distinct_user_count"
run_sql "ALTER TABLE security.alert_candidates ADD COLUMN IF NOT EXISTS source_kind LowCardinality(String) DEFAULT '' AFTER distinct_ip_count"
run_sql "ALTER TABLE security.alert_candidates ADD COLUMN IF NOT EXISTS reason String DEFAULT '' AFTER window_end"
run_sql "ALTER TABLE security.alert_candidates ADD COLUMN IF NOT EXISTS evidence_summary String DEFAULT '' AFTER reason"
run_sql "ALTER TABLE security.alert_candidates ADD COLUMN IF NOT EXISTS workflow_state LowCardinality(String) DEFAULT 'new' AFTER evidence_summary"
run_sql_file "${ROOT_DIR}/configs/clickhouse/initdb/03_create_endpoint_activity_view.sql"
run_sql_file "${ROOT_DIR}/configs/clickhouse/initdb/04_create_recent_login_detections_view.sql"
run_sql_file "${ROOT_DIR}/configs/clickhouse/initdb/05_create_auth_events_view.sql"

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

recent_detections_exists="$(query_scalar "SELECT count() FROM system.tables WHERE database = 'security' AND name = 'recent_login_detections' FORMAT TabSeparated")"
if [[ "${recent_detections_exists}" != "1" ]]; then
  printf "[%s] ERROR: recent_login_detections view missing after migration\n" "$(timestamp)" >&2
  exit 1
fi

auth_events_exists="$(query_scalar "SELECT count() FROM system.tables WHERE database = 'security' AND name = 'auth_events' FORMAT TabSeparated")"
if [[ "${auth_events_exists}" != "1" ]]; then
  printf "[%s] ERROR: auth_events view missing after migration\n" "$(timestamp)" >&2
  exit 1
fi

window_bucket_exists="$(query_scalar "SELECT count() FROM system.columns WHERE database = 'security' AND table = 'alert_candidates' AND name = 'window_bucket' FORMAT TabSeparated")"
if [[ "${window_bucket_exists}" != "1" ]]; then
  printf "[%s] ERROR: alert_candidates.window_bucket missing after migration\n" "$(timestamp)" >&2
  exit 1
fi

printf "[%s] Migration complete: security.events.schema_version + security.auth_events + security.alert_candidates + security.endpoint_activity + security.recent_login_detections ready\n" "$(timestamp)"
