#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "${ROOT_DIR}"

CLICKHOUSE_URL="${ENDPOINT_REPORT_CLICKHOUSE_URL:-http://localhost:8123/}"
LANE_FILTER="${ENDPOINT_REPORT_LANE:-}"
LIMIT="${ENDPOINT_REPORT_LIMIT:-25}"
MIN_ENDPOINTS="${ENDPOINT_REPORT_MIN_ENDPOINTS:-0}"

usage() {
  cat <<'EOF'
Usage:
  ./scripts/endpoint-activity-report.sh [options]

Options:
  --lane <ingest_source>   Filter by lane (for example vector-windows-endpoint)
  --limit <n>              Max rows to print (default: 25)
  --min-endpoints <n>      Fail if fewer endpoints are observed (default: 0)
  --clickhouse-url <url>   ClickHouse HTTP URL (default: http://localhost:8123/)
  -h, --help               Show this help
EOF
}

while [[ $# -gt 0 ]]; do
  case "$1" in
    --lane)
      LANE_FILTER="${2:-}"
      shift 2
      ;;
    --limit)
      LIMIT="${2:-}"
      shift 2
      ;;
    --min-endpoints)
      MIN_ENDPOINTS="${2:-}"
      shift 2
      ;;
    --clickhouse-url)
      CLICKHOUSE_URL="${2:-}"
      shift 2
      ;;
    -h|--help)
      usage
      exit 0
      ;;
    *)
      echo "ERROR: unknown argument: $1" >&2
      usage
      exit 1
      ;;
  esac
done

run_clickhouse_query() {
  local query="$1"
  local output

  if output="$(curl -fsS "${CLICKHOUSE_URL}" --data-binary "${query}" 2>/dev/null)"; then
    printf "%s" "${output}"
    return 0
  fi

  docker compose exec -T clickhouse clickhouse-client --query "${query}"
}

where_clause=""
if [[ -n "${LANE_FILTER}" ]]; then
  where_clause="WHERE lane = '${LANE_FILTER}'"
fi

count_query="SELECT count() FROM security.endpoint_activity ${where_clause} FORMAT TabSeparated"
endpoint_count="$(run_clickhouse_query "${count_query}" | tr -d '\r\n')"

if [[ ! "${endpoint_count}" =~ ^[0-9]+$ ]]; then
  echo "ERROR: unexpected endpoint count response: ${endpoint_count}" >&2
  exit 1
fi

echo "Observed endpoints: ${endpoint_count}"
if [[ -n "${LANE_FILTER}" ]]; then
  echo "Lane filter: ${LANE_FILTER}"
fi

if (( endpoint_count < MIN_ENDPOINTS )); then
  echo "ERROR: expected at least ${MIN_ENDPOINTS} endpoint(s), found ${endpoint_count}" >&2
  exit 1
fi

report_query="SELECT endpoint_id, lane, status, minutes_since_last_seen, total_events, first_seen, last_seen FROM security.endpoint_activity ${where_clause} ORDER BY last_seen DESC LIMIT ${LIMIT} FORMAT PrettyCompact"
run_clickhouse_query "${report_query}"
