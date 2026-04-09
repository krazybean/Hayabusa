#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "${ROOT_DIR}"

CLICKHOUSE_URL="${WINDOWS_CHECK_CLICKHOUSE_URL:-http://localhost:8123/}"
LOOKBACK_MINUTES="${WINDOWS_CHECK_LOOKBACK_MINUTES:-60}"
MIN_EVENTS="${WINDOWS_CHECK_MIN_EVENTS:-1}"
INGEST_SOURCE="${WINDOWS_CHECK_INGEST_SOURCE:-vector-windows-endpoint}"
EXPECTED_COMPUTER="${WINDOWS_CHECK_COMPUTER:-}"

usage() {
  cat <<'EOF'
Usage:
  ./scripts/windows-endpoint-check.sh [options]

Options:
  --computer <value>        Expected computer name in Windows event payloads
  --lookback-minutes <n>    Event lookback window (default: 60)
  --min-events <n>          Minimum expected events (default: 1)
  --ingest-source <value>   Ingest source to check (default: vector-windows-endpoint)
  --clickhouse-url <url>    ClickHouse HTTP URL (default: http://localhost:8123/)
  -h, --help                Show this help
EOF
}

while [[ $# -gt 0 ]]; do
  case "$1" in
    --computer)
      EXPECTED_COMPUTER="${2:-}"
      shift 2
      ;;
    --lookback-minutes)
      LOOKBACK_MINUTES="${2:-}"
      shift 2
      ;;
    --min-events)
      MIN_EVENTS="${2:-}"
      shift 2
      ;;
    --ingest-source)
      INGEST_SOURCE="${2:-}"
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

computer_filter=""
if [[ -n "${EXPECTED_COMPUTER}" ]]; then
  computer_filter=" AND lowerUTF8(ifNull(fields['computer'], '')) = lowerUTF8('${EXPECTED_COMPUTER}')"
fi

count_query="SELECT count() FROM security.events WHERE ingest_source='${INGEST_SOURCE}'${computer_filter} AND ts >= now() - INTERVAL ${LOOKBACK_MINUTES} MINUTE FORMAT TabSeparated"
event_count="$(run_clickhouse_query "${count_query}" | tr -d '\r\n')"

if [[ ! "${event_count}" =~ ^[0-9]+$ ]]; then
  echo "ERROR: unexpected count response: ${event_count}" >&2
  exit 1
fi

if [[ -n "${EXPECTED_COMPUTER}" ]]; then
  echo "Windows endpoint events in last ${LOOKBACK_MINUTES}m (${EXPECTED_COMPUTER}): ${event_count}"
else
  echo "Windows endpoint events in last ${LOOKBACK_MINUTES}m: ${event_count}"
fi

if (( event_count < MIN_EVENTS )); then
  echo "ERROR: expected at least ${MIN_EVENTS} events from ${INGEST_SOURCE}" >&2
  exit 1
fi

latest_query="SELECT ts, ingest_source, fields['computer'] AS computer, fields['channel'] AS channel, fields['event_id'] AS event_id, message FROM security.events WHERE ingest_source='${INGEST_SOURCE}'${computer_filter} ORDER BY ts DESC LIMIT 10 FORMAT PrettyCompact"
run_clickhouse_query "${latest_query}"
