#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
TARGET_FILE="${1:-${ROOT_DIR}/data/host-logs/windows-events.log}"
COMPUTER_NAME="${WINDOWS_EVENT_COMPUTER:-WIN-LOCAL-SIM}"
EVENT_IDS_RAW="${WINDOWS_SECURITY_EVENT_IDS:-4625,4625,4625,4740,4697,4728,7045}"

message_for_event_id() {
  case "$1" in
    4625) echo "An account failed to log on (4625)" ;;
    4740) echo "A user account was locked out (4740)" ;;
    4697) echo "A service was installed in the system (4697)" ;;
    7045) echo "A new service was installed (7045)" ;;
    4728) echo "A member was added to a security-enabled global group (4728)" ;;
    4732) echo "A member was added to a security-enabled local group (4732)" ;;
    4756) echo "A member was added to a security-enabled universal group (4756)" ;;
    *) echo "Windows security event (${1})" ;;
  esac
}

level_for_event_id() {
  case "$1" in
    4625|4740|4697|7045|4728|4732|4756) echo "Warning" ;;
    *) echo "Information" ;;
  esac
}

mkdir -p "$(dirname "${TARGET_FILE}")"
IFS=',' read -r -a event_ids <<<"${EVENT_IDS_RAW}"

written=0
for event_id in "${event_ids[@]}"; do
  trimmed="$(echo "${event_id}" | tr -d '[:space:]')"
  [[ -n "${trimmed}" ]] || continue

  message="$(message_for_event_id "${trimmed}")"
  level="$(level_for_event_id "${trimmed}")"

  printf '{"Message":"%s","EventID":%s,"Channel":"Security","Computer":"%s","ProviderName":"Microsoft-Windows-Security-Auditing","Level":"%s","Keywords":"Audit","TimeGenerated":"%s"}\n' \
    "${message}" \
    "${trimmed}" \
    "${COMPUTER_NAME}" \
    "${level}" \
    "$(date -u +"%Y-%m-%dT%H:%M:%SZ")" >>"${TARGET_FILE}"
  written=$((written + 1))
done

echo "Wrote ${written} Windows security scenario events to ${TARGET_FILE}"
