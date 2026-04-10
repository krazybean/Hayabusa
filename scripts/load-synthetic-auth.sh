#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT_DIR="$(cd "${SCRIPT_DIR}/.." && pwd)"
SCENARIO_DIR="${ROOT_DIR}/configs/synthetic-auth/scenarios"
TARGET_DIR="${ROOT_DIR}/data/synthetic-auth"
SCENARIO="all"
CLEAR_EXISTING=false

usage() {
  cat <<'EOF'
Usage: ./scripts/load-synthetic-auth.sh [--scenario NAME|all] [--clear] [--list]

Copy deterministic synthetic auth scenarios into the Vector file source directory.
These events are intentionally labeled with ingest_source = synthetic-auth.
EOF
}

list_scenarios() {
  find "${SCENARIO_DIR}" -maxdepth 1 -type f -name '*.jsonl' -exec basename {} .jsonl \; | sort
}

while [[ $# -gt 0 ]]; do
  case "$1" in
    --scenario)
      SCENARIO="${2:-}"
      shift 2
      ;;
    --clear)
      CLEAR_EXISTING=true
      shift
      ;;
    --list)
      list_scenarios
      exit 0
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

mkdir -p "${TARGET_DIR}"

if [[ "${CLEAR_EXISTING}" == "true" ]]; then
  find "${TARGET_DIR}" -maxdepth 1 -type f -name '*.jsonl' -delete
fi

copy_scenario() {
  local scenario_name="$1"
  local source_file="${SCENARIO_DIR}/${scenario_name}.jsonl"
  local timestamp
  local target_file
  local run_id

  if [[ ! -f "${source_file}" ]]; then
    printf 'Unknown synthetic auth scenario: %s\n' "${scenario_name}" >&2
    exit 1
  fi

  timestamp="$(date -u +"%Y%m%dT%H%M%SZ")"
  target_file="${TARGET_DIR}/${timestamp}-${scenario_name}.jsonl"
  run_id="${timestamp}-${scenario_name}"
  while IFS= read -r line; do
    [[ -n "${line}" ]] || continue
    line_timestamp="$(date -u +"%Y-%m-%dT%H:%M:%SZ")"
    printf '%s\n' "${line}" | sed "s/}$/,\"timestamp\":\"${line_timestamp}\",\"run_id\":\"${run_id}\"}/"
  done < "${source_file}" > "${target_file}"
  printf 'Loaded %s -> %s (%s events)\n' "${scenario_name}" "${target_file}" "$(wc -l < "${target_file}" | tr -d ' ')"
}

if [[ "${SCENARIO}" == "all" ]]; then
  while IFS= read -r scenario_name; do
    copy_scenario "${scenario_name}"
    sleep 1
  done < <(list_scenarios)
else
  copy_scenario "${SCENARIO}"
fi

cat <<'EOF'

Next steps:
  1. Wait a few seconds for Vector to read the new file(s).
  2. Run ./scripts/check-auth-events.sh to confirm security.events and security.auth_events are populated.
  3. Run ./scripts/recent-detections.sh after the detection poll interval to inspect detections.
EOF
