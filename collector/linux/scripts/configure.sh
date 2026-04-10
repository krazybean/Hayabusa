#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/../../.." && pwd)"
TEMPLATE_PATH="${LINUX_COLLECTOR_TEMPLATE_PATH:-${ROOT_DIR}/collector/linux/vector/vector.toml.tpl}"
COLLECTOR_ROOT="${LINUX_COLLECTOR_ROOT:-/etc/hayabusa/collector/linux}"
NATS_URL=""
SUBJECT="${LINUX_COLLECTOR_SUBJECT:-events.auth}"
COLLECTOR_NAME="$(hostname -s 2>/dev/null || hostname)"
OUTPUT_PATH=""

usage() {
  cat <<'EOF'
Usage:
  ./collector/linux/scripts/configure.sh --nats-url <url> [options]

Options:
  --nats-url <url>        NATS endpoint for Hayabusa ingestion
  --subject <subject>     NATS subject (default: events.auth)
  --collector-name <id>   Collector name / host label (default: local hostname)
  --collector-root <dir>  Collector root (default: /etc/hayabusa/collector/linux)
  --output <path>         Output config path (default: <collector-root>/config/vector.toml)
  -h, --help              Show this help
EOF
}

while [[ $# -gt 0 ]]; do
  case "$1" in
    --nats-url)
      NATS_URL="${2:-}"
      shift 2
      ;;
    --subject)
      SUBJECT="${2:-}"
      shift 2
      ;;
    --collector-name)
      COLLECTOR_NAME="${2:-}"
      shift 2
      ;;
    --collector-root)
      COLLECTOR_ROOT="${2:-}"
      shift 2
      ;;
    --output)
      OUTPUT_PATH="${2:-}"
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

if [[ -z "${NATS_URL}" ]]; then
  echo "ERROR: --nats-url is required" >&2
  exit 1
fi

if [[ ! -f "${TEMPLATE_PATH}" ]]; then
  echo "ERROR: template not found: ${TEMPLATE_PATH}" >&2
  exit 1
fi

mkdir -p "${COLLECTOR_ROOT}/config" "${COLLECTOR_ROOT}/state"

if [[ -z "${OUTPUT_PATH}" ]]; then
  OUTPUT_PATH="${COLLECTOR_ROOT}/config/vector.toml"
fi

sed \
  -e "s|__NATS_URL__|${NATS_URL}|g" \
  -e "s|__NATS_SUBJECT__|${SUBJECT}|g" \
  -e "s|__COLLECTOR_NAME__|${COLLECTOR_NAME}|g" \
  -e "s|__STATE_DIR__|${COLLECTOR_ROOT}/state|g" \
  "${TEMPLATE_PATH}" > "${OUTPUT_PATH}"

echo "[hayabusa-linux-collector] rendered config"
echo "  config path : ${OUTPUT_PATH}"
echo "  nats url    : ${NATS_URL}"
echo "  subject     : ${SUBJECT}"
echo "  collector   : ${COLLECTOR_NAME}"

