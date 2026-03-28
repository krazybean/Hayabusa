#!/usr/bin/env bash
set -euo pipefail

CLICKHOUSE_URL="${WINDOWS_CHECK_CLICKHOUSE_URL:-http://localhost:8123/}"
LOOKBACK_MINUTES="${WINDOWS_CHECK_LOOKBACK_MINUTES:-60}"
MIN_EVENTS="${WINDOWS_CHECK_MIN_EVENTS:-1}"
INGEST_SOURCE="${WINDOWS_CHECK_INGEST_SOURCE:-vector-windows-endpoint}"

count_query="SELECT count() FROM security.events WHERE ingest_source='${INGEST_SOURCE}' AND ts >= now() - INTERVAL ${LOOKBACK_MINUTES} MINUTE FORMAT TabSeparated"
event_count="$(curl -fsS "${CLICKHOUSE_URL}" --data-binary "${count_query}" | tr -d '\r\n')"

if [[ ! "${event_count}" =~ ^[0-9]+$ ]]; then
  echo "ERROR: unexpected count response: ${event_count}" >&2
  exit 1
fi

echo "Windows endpoint events in last ${LOOKBACK_MINUTES}m: ${event_count}"

if (( event_count < MIN_EVENTS )); then
  echo "ERROR: expected at least ${MIN_EVENTS} events from ${INGEST_SOURCE}" >&2
  exit 1
fi

latest_query="SELECT ts, ingest_source, fields['computer'] AS computer, fields['event_id'] AS event_id, message FROM security.events WHERE ingest_source='${INGEST_SOURCE}' ORDER BY ts DESC LIMIT 10 FORMAT PrettyCompact"
curl -fsS "${CLICKHOUSE_URL}" --data-binary "${latest_query}"
