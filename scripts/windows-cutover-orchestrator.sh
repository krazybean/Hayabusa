#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "${ROOT_DIR}"

ENDPOINT_ID=""
VECTOR_HOST=""
EXPECTED_CIDR=""
COMPUTER=""
LOOKBACK_MINUTES="${WINDOWS_CUTOVER_LOOKBACK_MINUTES:-60}"
MIN_EVENTS="${WINDOWS_CUTOVER_MIN_EVENTS:-1}"
OUTPUT_DIR="${WINDOWS_CUTOVER_OUTPUT_DIR:-${ROOT_DIR}/dist/windows-endpoints}"
INCLUDE_LOOPBACK=false
ALLOW_BROAD_ORIGINS=false
FORCE_BUNDLE=false
SKIP_RESTART=false
DRY_RUN=false

usage() {
  cat <<'EOF'
Usage:
  ./scripts/windows-cutover-orchestrator.sh \
    --endpoint-id <id> \
    --vector-host <host-or-ip> \
    --expected-cidr <cidr> \
    --computer <name> [options]

Required:
  --endpoint-id <id>         Endpoint ID used for client cert + bundle path
  --vector-host <host-or-ip> Reachable Hayabusa host/IP for Vector lane 24225
  --expected-cidr <cidr>     Endpoint/network CIDR to keep in permit_origin (e.g. 192.168.10.22/32)
  --computer <name>          Expected Windows Computer value in events

Options:
  --lookback-minutes <n>     Validation lookback window (default: 60)
  --min-events <n>           Minimum expected endpoint events (default: 1)
  --output-dir <path>        Enrollment bundle output base (default: dist/windows-endpoints)
  --include-loopback         Keep 127.0.0.0/8 in permit_origin for local test flows
  --allow-broad-origins      Allow broad CIDRs during final cutover check (lab-only)
  --force-bundle             Overwrite existing endpoint bundle directory
  --skip-restart             Skip Vector restart after permit_origin update
  --dry-run                  Print commands only; do not change files/services
  -h, --help                 Show this help
EOF
}

run_cmd() {
  if [[ "${DRY_RUN}" == "true" ]]; then
    printf '[dry-run] %q' "$1"
    shift || true
    for arg in "$@"; do
      printf ' %q' "${arg}"
    done
    printf '\n'
    return 0
  fi
  "$@"
}

while [[ $# -gt 0 ]]; do
  case "$1" in
    --endpoint-id)
      ENDPOINT_ID="${2:-}"
      shift 2
      ;;
    --vector-host)
      VECTOR_HOST="${2:-}"
      shift 2
      ;;
    --expected-cidr)
      EXPECTED_CIDR="${2:-}"
      shift 2
      ;;
    --computer)
      COMPUTER="${2:-}"
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
    --output-dir)
      OUTPUT_DIR="${2:-}"
      shift 2
      ;;
    --include-loopback)
      INCLUDE_LOOPBACK=true
      shift
      ;;
    --allow-broad-origins)
      ALLOW_BROAD_ORIGINS=true
      shift
      ;;
    --force-bundle)
      FORCE_BUNDLE=true
      shift
      ;;
    --skip-restart)
      SKIP_RESTART=true
      shift
      ;;
    --dry-run)
      DRY_RUN=true
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

if [[ -z "${ENDPOINT_ID}" || -z "${VECTOR_HOST}" || -z "${EXPECTED_CIDR}" || -z "${COMPUTER}" ]]; then
  usage
  exit 1
fi

if ! [[ "${MIN_EVENTS}" =~ ^[0-9]+$ && "${LOOKBACK_MINUTES}" =~ ^[0-9]+$ ]]; then
  echo "ERROR: --lookback-minutes and --min-events must be integers." >&2
  exit 1
fi

echo "== Hayabusa Windows Cutover Orchestrator =="
echo "endpoint_id=${ENDPOINT_ID}"
echo "vector_host=${VECTOR_HOST}"
echo "expected_cidr=${EXPECTED_CIDR}"
echo "computer=${COMPUTER}"
echo "output_dir=${OUTPUT_DIR}"
echo "dry_run=${DRY_RUN}"
echo

enroll_cmd=(./scripts/enroll-windows-endpoint.sh --endpoint-id "${ENDPOINT_ID}" --vector-host "${VECTOR_HOST}" --output-dir "${OUTPUT_DIR}")
if [[ "${FORCE_BUNDLE}" == "true" ]]; then
  enroll_cmd+=(--force)
fi

permit_cmd=(./scripts/set-windows-permit-origin.sh --cidr "${EXPECTED_CIDR}")
if [[ "${INCLUDE_LOOPBACK}" == "true" ]]; then
  permit_cmd+=(--include-loopback)
fi

cutover_cmd=(
  ./scripts/windows-real-host-cutover-check.sh
  --computer "${COMPUTER}"
  --expected-cidr "${EXPECTED_CIDR}"
  --lookback-minutes "${LOOKBACK_MINUTES}"
  --min-events "${MIN_EVENTS}"
)
if [[ "${ALLOW_BROAD_ORIGINS}" == "true" ]]; then
  cutover_cmd+=(--allow-broad-origins)
fi

echo "[1/4] Building endpoint enrollment bundle..."
run_cmd "${enroll_cmd[@]}"

echo "[2/4] Updating Vector Windows permit_origin..."
run_cmd "${permit_cmd[@]}"

if [[ "${SKIP_RESTART}" == "true" ]]; then
  echo "[3/4] Skipping Vector restart (--skip-restart)."
else
  echo "[3/4] Restarting Vector..."
  if [[ "${DRY_RUN}" == "true" ]]; then
    run_cmd /bin/bash -lc "DOCKER_CONFIG=/tmp/docker-nocreds docker compose up -d vector"
  else
    DOCKER_CONFIG=/tmp/docker-nocreds run_cmd /bin/bash -lc "docker compose up -d vector"
  fi
fi

echo "[4/4] Running real-host cutover checks..."
run_cmd "${cutover_cmd[@]}"

echo
echo "Cutover workflow completed."
echo "Copy endpoint bundle from:"
echo "  ${OUTPUT_DIR}/${ENDPOINT_ID}"
