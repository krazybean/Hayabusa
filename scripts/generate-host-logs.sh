#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
TARGET_FILE="${1:-${ROOT_DIR}/data/host-logs/linux-auth.log}"
EVENT_COUNT="${HOST_LOG_EVENT_COUNT:-4}"

mkdir -p "$(dirname "${TARGET_FILE}")"

for i in $(seq 1 "${EVENT_COUNT}"); do
  printf "%s sshd[%d]: Failed password for invalid user root from 10.10.0.%d port 22 ssh2\n" \
    "$(date -u +"%Y-%m-%dT%H:%M:%SZ")" \
    "$((4000 + i))" \
    "${i}" >>"${TARGET_FILE}"
done

printf "Wrote %s synthetic host-auth lines to %s\n" "${EVENT_COUNT}" "${TARGET_FILE}"
