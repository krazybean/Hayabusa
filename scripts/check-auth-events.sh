#!/usr/bin/env bash
set -euo pipefail

CLICKHOUSE_URL="${CLICKHOUSE_URL:-http://localhost:8123}"
LOOKBACK_MINUTES="${LOOKBACK_MINUTES:-60}"
LIMIT="${LIMIT:-20}"
SOURCE_KIND=""
USER_FILTER=""
SRC_IP_FILTER=""

usage() {
  cat <<'EOF'
Usage: ./scripts/check-auth-events.sh [--lookback-minutes N] [--limit N] [--source-kind KIND] [--user USER] [--src-ip IP]

Inspect recent synthetic auth events in both security.events and security.auth_events.
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
    --source-kind)
      SOURCE_KIND="${2:-}"
      shift 2
      ;;
    --user)
      USER_FILTER="${2:-}"
      shift 2
      ;;
    --src-ip)
      SRC_IP_FILTER="${2:-}"
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

events_where="ingest_source = 'synthetic-auth' AND ts > now() - INTERVAL ${LOOKBACK_MINUTES} MINUTE"
auth_where="${events_where}"

if [[ -n "${SOURCE_KIND}" ]]; then
  escaped_source_kind="$(escape_sql_string "${SOURCE_KIND}")"
  auth_where="${auth_where} AND source_kind = '${escaped_source_kind}'"
fi

if [[ -n "${USER_FILTER}" ]]; then
  escaped_user="$(escape_sql_string "${USER_FILTER}")"
  events_where="${events_where} AND fields['user'] = '${escaped_user}'"
  auth_where="${auth_where} AND user = '${escaped_user}'"
fi

if [[ -n "${SRC_IP_FILTER}" ]]; then
  escaped_src_ip="$(escape_sql_string "${SRC_IP_FILTER}")"
  events_where="${events_where} AND fields['src_ip'] = '${escaped_src_ip}'"
  auth_where="${auth_where} AND src_ip = '${escaped_src_ip}'"
fi

printf '\nRaw synthetic auth events (security.events)\n'
printf '%s\n' '-----------------------------------------'
run_query "
SELECT
  ts,
  platform,
  fields['scenario'] AS scenario,
  fields['user'] AS user,
  fields['src_ip'] AS src_ip,
  fields['status'] AS status,
  fields['source_kind'] AS source_kind,
  message
FROM security.events
WHERE ${events_where}
ORDER BY ts DESC
LIMIT ${LIMIT}
FORMAT PrettyCompact
"

printf '\nNormalized auth events (security.auth_events)\n'
printf '%s\n' '--------------------------------------------'
run_query "
SELECT
  ts,
  platform,
  user,
  src_ip,
  host,
  status,
  source_kind,
  raw_event_id,
  auth_method,
  collector_name,
  message
FROM security.auth_events
WHERE ${auth_where}
ORDER BY ts DESC
LIMIT ${LIMIT}
FORMAT PrettyCompact
"

printf '\nScenario summary\n'
printf '%s\n' '----------------'
run_query "
SELECT
  ifNull(nullIf(fields['scenario'], ''), 'unspecified') AS scenario,
  fields['status'] AS status,
  count() AS events
FROM security.events
WHERE ${events_where}
GROUP BY scenario, status
ORDER BY scenario ASC, status ASC
FORMAT PrettyCompact
"
