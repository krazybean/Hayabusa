#!/usr/bin/env bash
set -euo pipefail

CLICKHOUSE_URL="${CLICKHOUSE_URL:-http://localhost:8123}"
LOOKBACK_MINUTES="${LOOKBACK_MINUTES:-60}"
LIMIT="${LIMIT:-20}"
RULE_ID=""

usage() {
  cat <<'EOF'
Usage: ./scripts/recent-detections.sh [--lookback-minutes N] [--limit N] [--rule-id RULE_ID]

Show recent Hayabusa login detections with explainable context.
EOF
}

escape_sql_string() {
  printf '%s' "$1" | sed "s/'/''/g"
}

is_integer() {
  [[ "$1" =~ ^[0-9]+$ ]]
}

run_query() {
  local sql="$1"

  if curl -fsS "${CLICKHOUSE_URL}/ping" >/dev/null 2>&1; then
    curl -fsS "${CLICKHOUSE_URL}/" --data-binary "${sql}"
    return 0
  fi

  if command -v docker >/dev/null 2>&1; then
    docker compose exec -T clickhouse clickhouse-client --query "${sql}"
    return 0
  fi

  printf 'Could not reach ClickHouse over HTTP and docker compose exec is unavailable.\n' >&2
  return 1
}

while [[ $# -gt 0 ]]; do
  case "$1" in
    --lookback-minutes)
      LOOKBACK_MINUTES="${2:-}"
      shift 2
      ;;
    --limit)
      LIMIT="${2:-}"
      shift 2
      ;;
    --rule-id)
      RULE_ID="${2:-}"
      shift 2
      ;;
    -h|--help)
      usage
      exit 0
      ;;
    *)
      printf 'Unknown argument: %s\n' "$1" >&2
      usage >&2
      exit 1
      ;;
  esac
done

if ! is_integer "${LOOKBACK_MINUTES}"; then
  printf 'LOOKBACK_MINUTES must be an integer\n' >&2
  exit 1
fi

if ! is_integer "${LIMIT}"; then
  printf 'LIMIT must be an integer\n' >&2
  exit 1
fi

where_clause="ts > now() - INTERVAL ${LOOKBACK_MINUTES} MINUTE"
if [[ -n "${RULE_ID}" ]]; then
  escaped_rule_id="$(escape_sql_string "${RULE_ID}")"
  where_clause="${where_clause} AND rule_id = '${escaped_rule_id}'"
fi

run_query "
SELECT
  ts,
  alert_type,
  alert_fingerprint,
  rule_id,
  severity,
  attempt_count,
  entity_user,
  entity_src_ip,
  entity_host,
  window_bucket,
  distinct_user_count,
  distinct_ip_count,
  source_kind,
  reason,
  evidence_summary
FROM security.recent_login_detections
WHERE ${where_clause}
ORDER BY ts DESC
LIMIT ${LIMIT}
FORMAT PrettyCompact
"
