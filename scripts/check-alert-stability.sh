#!/usr/bin/env bash
set -euo pipefail

CLICKHOUSE_URL="${CLICKHOUSE_URL:-http://localhost:8123}"
LOOKBACK_MINUTES="${LOOKBACK_MINUTES:-60}"

usage() {
  cat <<'EOF'
Usage: ./scripts/check-alert-stability.sh [--lookback-minutes N]

Show duplicate and stability checks for Hayabusa alert candidates.
EOF
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

where_clause="ts > now() - INTERVAL ${LOOKBACK_MINUTES} MINUTE"

printf '\n== Recent totals by alert type ==\n'
run_query "
SELECT
  alert_type,
  count() AS alerts,
  uniqExact(alert_fingerprint) AS unique_fingerprints
FROM security.alert_candidates
WHERE ${where_clause}
GROUP BY alert_type
ORDER BY alert_type
FORMAT PrettyCompact
"

printf '\n== Duplicate fingerprints (should be empty) ==\n'
run_query "
SELECT
  alert_type,
  alert_fingerprint,
  count() AS duplicates
FROM security.alert_candidates
WHERE ${where_clause}
GROUP BY alert_type, alert_fingerprint
HAVING duplicates > 1
ORDER BY duplicates DESC, alert_type
FORMAT PrettyCompact
"

printf '\n== Duplicate entity/window buckets (should be empty) ==\n'
run_query "
SELECT
  alert_type,
  window_bucket,
  entity_user,
  entity_src_ip,
  entity_host,
  source_kind,
  count() AS duplicates
FROM security.alert_candidates
WHERE ${where_clause}
GROUP BY alert_type, window_bucket, entity_user, entity_src_ip, entity_host, source_kind
HAVING duplicates > 1
ORDER BY duplicates DESC, alert_type, window_bucket DESC
FORMAT PrettyCompact
"

printf '\n== Recent alert windows ==\n'
run_query "
SELECT
  ts,
  alert_type,
  window_bucket,
  entity_user,
  entity_src_ip,
  entity_host,
  attempt_count,
  distinct_user_count,
  distinct_ip_count,
  reason
FROM security.recent_login_detections
WHERE ${where_clause}
ORDER BY ts DESC
LIMIT 20
FORMAT PrettyCompact
"
