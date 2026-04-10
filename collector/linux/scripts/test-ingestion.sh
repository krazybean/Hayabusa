#!/usr/bin/env bash
set -euo pipefail

COLLECTOR_ROOT="${LINUX_COLLECTOR_ROOT:-/etc/hayabusa/collector/linux}"
CONFIG_PATH=""
LOOKBACK_LINES="${LINUX_COLLECTOR_LOOKBACK_LINES:-20}"

usage() {
  cat <<'EOF'
Usage:
  ./collector/linux/scripts/test-ingestion.sh [options]

Options:
  --collector-root <dir>   Collector root (default: /etc/hayabusa/collector/linux)
  --config <path>          Rendered Vector config path
  --lookback-lines <n>     Number of recent auth lines to show (default: 20)
  -h, --help               Show this help
EOF
}

while [[ $# -gt 0 ]]; do
  case "$1" in
    --collector-root)
      COLLECTOR_ROOT="${2:-}"
      shift 2
      ;;
    --config)
      CONFIG_PATH="${2:-}"
      shift 2
      ;;
    --lookback-lines)
      LOOKBACK_LINES="${2:-}"
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

if [[ -z "${CONFIG_PATH}" ]]; then
  CONFIG_PATH="${COLLECTOR_ROOT}/config/vector.toml"
fi

auth_log=""
for candidate in /var/log/auth.log /var/log/secure; do
  if [[ -f "${candidate}" ]]; then
    auth_log="${candidate}"
    break
  fi
done

echo "[hayabusa-linux-collector] auth log discovery"
if [[ -n "${auth_log}" ]]; then
  echo "  OK: found auth log at ${auth_log}"
else
  echo "  WARN: no supported auth log found at /var/log/auth.log or /var/log/secure"
fi

echo "[hayabusa-linux-collector] config check"
if [[ -f "${CONFIG_PATH}" ]]; then
  echo "  OK: config present at ${CONFIG_PATH}"
else
  echo "  WARN: config missing at ${CONFIG_PATH}"
fi

if command -v vector >/dev/null 2>&1 && [[ -f "${CONFIG_PATH}" ]]; then
  echo "[hayabusa-linux-collector] vector validate"
  vector validate --no-environment "${CONFIG_PATH}" || true
else
  echo "[hayabusa-linux-collector] Vector not available for config validation"
fi

if [[ -n "${auth_log}" ]]; then
  echo "[hayabusa-linux-collector] recent ssh auth lines"
  grep -E 'sshd.*(Failed password|Accepted (password|publickey))' "${auth_log}" | tail -n "${LOOKBACK_LINES}" || true
fi

if [[ -f "${CONFIG_PATH}" ]]; then
  nats_url="$(awk -F'= ' '/^url = / {gsub(/"/, "", $2); print $2; exit}' "${CONFIG_PATH}")"
  if [[ -n "${nats_url}" ]]; then
    host_port="${nats_url#nats://}"
    host="${host_port%%:*}"
    port="${host_port##*:}"
    echo "[hayabusa-linux-collector] nats connectivity"
    if command -v nc >/dev/null 2>&1; then
      if nc -z -w2 "${host}" "${port}" >/dev/null 2>&1; then
        echo "  OK: ${host}:${port} reachable"
      else
        echo "  WARN: ${host}:${port} not reachable"
      fi
    else
      echo "  WARN: nc not installed; skipping connectivity probe"
    fi
  fi
fi

cat <<EOF
[hayabusa-linux-collector] suggested tests
  Failed login:
    From another shell or host, try ssh baduser@<this-host> and enter the wrong password a few times.

  Successful login:
    From another shell or host, try ssh <real-user>@<this-host> and authenticate successfully.

  Interactive run:
    vector --config ${CONFIG_PATH}
EOF
