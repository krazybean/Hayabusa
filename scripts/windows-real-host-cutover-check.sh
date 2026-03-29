#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "${ROOT_DIR}"

VECTOR_CONFIG="${WINDOWS_CUTOVER_VECTOR_CONFIG:-${ROOT_DIR}/configs/vector/vector.yaml}"
EXPECTED_COMPUTER="${WINDOWS_CUTOVER_COMPUTER:-}"
EXPECTED_CIDR="${WINDOWS_CUTOVER_EXPECTED_CIDR:-}"
LOOKBACK_MINUTES="${WINDOWS_CUTOVER_LOOKBACK_MINUTES:-60}"
MIN_EVENTS="${WINDOWS_CUTOVER_MIN_EVENTS:-1}"
ALLOW_BROAD_ORIGINS="${WINDOWS_CUTOVER_ALLOW_BROAD_ORIGINS:-false}"

usage() {
  cat <<'EOF'
Usage:
  ./scripts/windows-real-host-cutover-check.sh --computer <name> --expected-cidr <cidr> [options]

Options:
  --computer <name>          Expected Windows Computer name in event payloads
  --expected-cidr <cidr>     Endpoint/network CIDR expected in Vector permit_origin (e.g., 192.168.10.22/32)
  --lookback-minutes <n>     Event lookback window (default: 60)
  --min-events <n>           Minimum expected events (default: 1)
  --allow-broad-origins      Allow default broad permit_origin CIDRs (not recommended)
  -h, --help                 Show this help
EOF
}

while [[ $# -gt 0 ]]; do
  case "$1" in
    --computer)
      EXPECTED_COMPUTER="${2:-}"
      shift 2
      ;;
    --expected-cidr)
      EXPECTED_CIDR="${2:-}"
      shift 2
      ;;
    --lookback-minutes)
      LOOKBACK_MINUTES="${2:-}"
      shift 2
      ;;
    --min-events)
      MIN_EVENTS="${2:-}"
      shift 2
      ;;
    --allow-broad-origins)
      ALLOW_BROAD_ORIGINS="true"
      shift
      ;;
    -h|--help)
      usage
      exit 0
      ;;
    *)
      echo "ERROR: Unknown argument: $1" >&2
      usage
      exit 1
      ;;
  esac
done

if [[ -z "${EXPECTED_COMPUTER}" || -z "${EXPECTED_CIDR}" ]]; then
  usage
  exit 1
fi

if [[ ! -f "${VECTOR_CONFIG}" ]]; then
  echo "ERROR: Vector config not found: ${VECTOR_CONFIG}" >&2
  exit 1
fi

if ! grep -Fq -- "${EXPECTED_CIDR}" "${VECTOR_CONFIG}"; then
  echo "ERROR: expected CIDR ${EXPECTED_CIDR} not found in ${VECTOR_CONFIG} permit_origin" >&2
  exit 1
fi

if [[ "${ALLOW_BROAD_ORIGINS}" != "true" ]]; then
  for broad_cidr in "10.0.0.0/8" "172.16.0.0/12" "192.168.0.0/16"; do
    if grep -Fq -- "${broad_cidr}" "${VECTOR_CONFIG}"; then
      echo "ERROR: broad permit_origin CIDR still present (${broad_cidr}) in ${VECTOR_CONFIG}" >&2
      echo "       Remove broad CIDRs or rerun with --allow-broad-origins for non-production validation." >&2
      exit 1
    fi
  done
fi

echo "Vector permit_origin check passed for ${EXPECTED_CIDR}."

WINDOWS_CHECK_COMPUTER="${EXPECTED_COMPUTER}" \
WINDOWS_CHECK_LOOKBACK_MINUTES="${LOOKBACK_MINUTES}" \
WINDOWS_CHECK_MIN_EVENTS="${MIN_EVENTS}" \
./scripts/windows-endpoint-check.sh

echo "Windows real-host cutover checks passed for computer=${EXPECTED_COMPUTER}."
