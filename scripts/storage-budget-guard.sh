#!/usr/bin/env bash
set -euo pipefail

# Soft/hard guardrail for local synthetic event volume in ClickHouse.
# Default budget: 1 GiB for security.events.

BUDGET_BYTES="${HAYABUSA_EVENTS_BUDGET_BYTES:-1073741824}"
WARN_RATIO="${HAYABUSA_EVENTS_WARN_RATIO:-0.90}"
PRUNE_PERCENT="${HAYABUSA_EVENTS_PRUNE_PERCENT:-20}"
MUTATIONS_SYNC="${HAYABUSA_EVENTS_MUTATIONS_SYNC:-1}"
CLICKHOUSE_URL="${CLICKHOUSE_URL:-http://localhost:8123/}"

ENFORCE=0

usage() {
  cat <<'EOF'
Usage:
  ./scripts/storage-budget-guard.sh [--enforce]

Options:
  --enforce  If over budget, delete oldest events in batches until under budget.
  -h, --help Show help.

Environment:
  HAYABUSA_EVENTS_BUDGET_BYTES   Budget in bytes (default: 1073741824, 1 GiB)
  HAYABUSA_EVENTS_WARN_RATIO     Warning threshold ratio (default: 0.90)
  HAYABUSA_EVENTS_PRUNE_PERCENT  Oldest percent to prune per pass when enforcing (default: 20)
  HAYABUSA_EVENTS_MUTATIONS_SYNC ClickHouse mutations_sync value (default: 1)
  CLICKHOUSE_URL                 ClickHouse HTTP endpoint (default: http://localhost:8123/)
EOF
}

for arg in "$@"; do
  case "$arg" in
    --enforce) ENFORCE=1 ;;
    -h|--help) usage; exit 0 ;;
    *)
      echo "Unknown argument: $arg" >&2
      usage >&2
      exit 1
      ;;
  esac
done

ch_query() {
  local sql="$1"
  curl -fsS "${CLICKHOUSE_URL}" --data-binary "${sql}" | tr -d '\r\n'
}

is_integer() {
  [[ "$1" =~ ^[0-9]+$ ]]
}

bytes_to_human() {
  awk -v b="$1" 'BEGIN {
    if (b < 1024) { printf "%d B", b; exit }
    if (b < 1048576) { printf "%.2f KiB", b/1024; exit }
    if (b < 1073741824) { printf "%.2f MiB", b/1048576; exit }
    printf "%.2f GiB", b/1073741824
  }'
}

table_bytes() {
  ch_query "SELECT toUInt64(ifNull(sum(bytes_on_disk), 0)) FROM system.parts WHERE active AND database = 'security' AND table = 'events' FORMAT TabSeparated"
}

table_rows() {
  ch_query "SELECT count() FROM security.events FORMAT TabSeparated"
}

warn_bytes="$(awk -v b="${BUDGET_BYTES}" -v r="${WARN_RATIO}" 'BEGIN { printf "%.0f", b * r }')"
if ! is_integer "${warn_bytes}"; then
  echo "Failed to compute warning threshold." >&2
  exit 1
fi

bytes_now="$(table_bytes)"
if ! is_integer "${bytes_now}"; then
  echo "Failed to query ClickHouse table size. Check ${CLICKHOUSE_URL}." >&2
  exit 1
fi

echo "security.events storage: ${bytes_now} bytes ($(bytes_to_human "${bytes_now}"))"
echo "Budget: ${BUDGET_BYTES} bytes ($(bytes_to_human "${BUDGET_BYTES}")), warn at ${warn_bytes} bytes ($(bytes_to_human "${warn_bytes}"))"

if (( bytes_now <= warn_bytes )); then
  echo "Status: OK (below warning threshold)."
  exit 0
fi

if (( bytes_now <= BUDGET_BYTES )); then
  echo "Status: WARNING (above warning threshold, below hard budget)."
  exit 0
fi

echo "Status: OVER BUDGET."
if (( ENFORCE == 0 )); then
  echo "Run with --enforce to prune oldest synthetic events until under budget."
  exit 2
fi

quantile="$(awk -v p="${PRUNE_PERCENT}" 'BEGIN { printf "%.6f", p / 100 }')"
for pass in 1 2 3 4 5 6; do
  current_rows="$(table_rows)"
  if ! is_integer "${current_rows}" || (( current_rows == 0 )); then
    echo "No rows available to prune."
    break
  fi

  cutoff_ms="$(ch_query "SELECT toInt64(ifNull(toUnixTimestamp64Milli(quantileExact(${quantile})(ts)), 0)) FROM security.events FORMAT TabSeparated")"
  if ! [[ "${cutoff_ms}" =~ ^-?[0-9]+$ ]] || (( cutoff_ms <= 0 )); then
    echo "Could not compute prune cutoff timestamp."
    break
  fi

  echo "Prune pass ${pass}: deleting oldest ~${PRUNE_PERCENT}% of events (cutoff ms=${cutoff_ms})."
  ch_query "ALTER TABLE security.events DELETE WHERE ts <= fromUnixTimestamp64Milli(${cutoff_ms}, 'UTC') SETTINGS mutations_sync = ${MUTATIONS_SYNC}"

  bytes_now="$(table_bytes)"
  echo "Post-prune size: ${bytes_now} bytes ($(bytes_to_human "${bytes_now}"))"
  if (( bytes_now <= BUDGET_BYTES )); then
    echo "Status: back under budget."
    exit 0
  fi
done

echo "Still over budget after prune passes; consider manual truncate for synthetic datasets:"
echo "  curl -s ${CLICKHOUSE_URL} --data-binary \"TRUNCATE TABLE security.events\""
exit 3
