#!/usr/bin/env bash
set -euo pipefail

COLLECTOR_ROOT="${LINUX_COLLECTOR_ROOT:-/etc/hayabusa/collector/linux}"

usage() {
  cat <<'EOF'
Usage:
  ./collector/linux/scripts/uninstall.sh [--collector-root <dir>]
EOF
}

while [[ $# -gt 0 ]]; do
  case "$1" in
    --collector-root)
      COLLECTOR_ROOT="${2:-}"
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

if [[ "$(id -u)" -ne 0 ]]; then
  echo "ERROR: run this script as root or with sudo." >&2
  exit 1
fi

if [[ ! -d "${COLLECTOR_ROOT}" ]]; then
  echo "[hayabusa-linux-collector] nothing to remove at ${COLLECTOR_ROOT}"
  exit 0
fi

rm -rf "${COLLECTOR_ROOT}"
echo "[hayabusa-linux-collector] removed ${COLLECTOR_ROOT}"
echo "System auth logs were left untouched."

