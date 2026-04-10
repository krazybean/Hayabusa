#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/../../.." && pwd)"
COLLECTOR_ROOT="${LINUX_COLLECTOR_ROOT:-/etc/hayabusa/collector/linux}"
NATS_URL=""
SUBJECT="${LINUX_COLLECTOR_SUBJECT:-events.auth}"
COLLECTOR_NAME="$(hostname -s 2>/dev/null || hostname)"

usage() {
  cat <<'EOF'
Usage:
  ./collector/linux/scripts/install.sh [options]

Options:
  --nats-url <url>        NATS endpoint for Hayabusa ingestion
  --subject <subject>     NATS subject (default: events.auth)
  --collector-name <id>   Collector name / host label (default: local hostname)
  --collector-root <dir>  Collector root (default: /etc/hayabusa/collector/linux)
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

mkdir -p "${COLLECTOR_ROOT}/config" "${COLLECTOR_ROOT}/state"

if command -v vector >/dev/null 2>&1; then
  echo "[hayabusa-linux-collector] detected Vector: $(command -v vector)"
else
  cat <<'EOF'
[hayabusa-linux-collector] Vector was not found.
Install Vector first, then rerun this script or run configure.sh directly.
Official install docs:
  https://vector.dev/docs/setup/installation/
EOF
fi

if [[ -n "${NATS_URL}" ]]; then
  "${ROOT_DIR}/collector/linux/scripts/configure.sh" \
    --nats-url "${NATS_URL}" \
    --subject "${SUBJECT}" \
    --collector-name "${COLLECTOR_NAME}" \
    --collector-root "${COLLECTOR_ROOT}"
fi

cat > "${COLLECTOR_ROOT}/README.txt" <<EOF
Hayabusa Linux SSH Collector
Collector root : ${COLLECTOR_ROOT}
Config path    : ${COLLECTOR_ROOT}/config/vector.toml
State dir      : ${COLLECTOR_ROOT}/state

Next steps:
1. Ensure Vector is installed on this Linux host.
2. Validate config:
   vector validate --no-environment ${COLLECTOR_ROOT}/config/vector.toml
3. Run interactively first:
   vector --config ${COLLECTOR_ROOT}/config/vector.toml
4. Test locally:
   ${ROOT_DIR}/collector/linux/scripts/test-ingestion.sh --collector-root ${COLLECTOR_ROOT}

TODO:
- add a minimal service wrapper only after the first real host path is stable
- validate distro-specific auth log differences on more real hosts
EOF

echo "[hayabusa-linux-collector] install staging complete"
echo "  collector root : ${COLLECTOR_ROOT}"
echo "  readme         : ${COLLECTOR_ROOT}/README.txt"

