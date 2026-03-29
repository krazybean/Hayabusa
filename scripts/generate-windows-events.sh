#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
TARGET_FILE="${1:-${ROOT_DIR}/data/host-logs/windows-events.log}"
EVENT_COUNT="${WINDOWS_EVENT_COUNT:-4}"
COMPUTER_NAME="${WINDOWS_EVENT_COMPUTER:-WIN-LOCAL-SIM}"

mkdir -p "$(dirname "${TARGET_FILE}")"

for i in $(seq 1 "${EVENT_COUNT}"); do
  event_id=$((4624 + (i % 2)))
  level="Information"
  if (( event_id == 4625 )); then
    level="Warning"
  fi

  printf '{"Message":"An account logon event occurred (%d)","EventID":%d,"Channel":"Security","Computer":"%s","ProviderName":"Microsoft-Windows-Security-Auditing","Level":"%s","Keywords":"Audit","TimeGenerated":"%s"}\n' \
    "${event_id}" \
    "${event_id}" \
    "${COMPUTER_NAME}" \
    "${level}" \
    "$(date -u +"%Y-%m-%dT%H:%M:%SZ")" >>"${TARGET_FILE}"
done

printf "Wrote %s synthetic Windows event lines to %s\n" "${EVENT_COUNT}" "${TARGET_FILE}"
