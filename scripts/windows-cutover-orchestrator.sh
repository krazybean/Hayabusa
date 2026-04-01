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
SKIP_POLICY_CHECK=false
POLICY_FILE="${WINDOWS_CUTOVER_POLICY_FILE:-${ROOT_DIR}/configs/endpoints/windows-endpoints.yaml}"
POLICY_SOFT_FAIL=true
PROMOTE_REQUIRED_ON_SUCCESS=false
PROMOTION_MAX_STALE_MINUTES="${WINDOWS_CUTOVER_PROMOTION_MAX_STALE_MINUTES:-120}"
FIRST_REAL_HOST=false
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
  --skip-policy-check        Skip endpoint policy drift check
  --policy-file <path>       Endpoint policy YAML (default: configs/endpoints/windows-endpoints.yaml)
  --policy-hard-fail         Fail orchestrator if policy drift check detects required drift
  --promote-required-on-success
                             Promote endpoint policy entry to required=true after successful checks
  --promotion-max-stale-minutes <n>
                             Set max_stale_minutes when promoting required endpoint (default: 120)
  --first-real-host          Convenience mode: promote required on success + post-promotion hard check
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
    --skip-policy-check)
      SKIP_POLICY_CHECK=true
      shift
      ;;
    --policy-file)
      POLICY_FILE="${2:-}"
      shift 2
      ;;
    --policy-hard-fail)
      POLICY_SOFT_FAIL=false
      shift
      ;;
    --promote-required-on-success)
      PROMOTE_REQUIRED_ON_SUCCESS=true
      shift
      ;;
    --promotion-max-stale-minutes)
      PROMOTION_MAX_STALE_MINUTES="${2:-}"
      shift 2
      ;;
    --first-real-host)
      FIRST_REAL_HOST=true
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

if ! [[ "${PROMOTION_MAX_STALE_MINUTES}" =~ ^[0-9]+$ ]]; then
  echo "ERROR: --promotion-max-stale-minutes must be an integer." >&2
  exit 1
fi

if [[ "${FIRST_REAL_HOST}" == "true" ]]; then
  PROMOTE_REQUIRED_ON_SUCCESS=true
  POLICY_SOFT_FAIL=true
fi

echo "== Hayabusa Windows Cutover Orchestrator =="
echo "endpoint_id=${ENDPOINT_ID}"
echo "vector_host=${VECTOR_HOST}"
echo "expected_cidr=${EXPECTED_CIDR}"
echo "computer=${COMPUTER}"
echo "output_dir=${OUTPUT_DIR}"
echo "policy_file=${POLICY_FILE}"
echo "promote_required_on_success=${PROMOTE_REQUIRED_ON_SUCCESS}"
echo "first_real_host=${FIRST_REAL_HOST}"
echo "dry_run=${DRY_RUN}"
echo

enroll_cmd=(
  ./scripts/enroll-windows-endpoint.sh
  --endpoint-id "${ENDPOINT_ID}"
  --vector-host "${VECTOR_HOST}"
  --output-dir "${OUTPUT_DIR}"
  --policy-file "${POLICY_FILE}"
)
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

echo "[1/6] Building endpoint enrollment bundle..."
run_cmd "${enroll_cmd[@]}"

echo "[2/6] Updating Vector Windows permit_origin..."
run_cmd "${permit_cmd[@]}"

if [[ "${SKIP_RESTART}" == "true" ]]; then
  echo "[3/6] Skipping Vector restart (--skip-restart)."
else
  echo "[3/6] Restarting Vector..."
  if [[ "${DRY_RUN}" == "true" ]]; then
    run_cmd /bin/bash -lc "DOCKER_CONFIG=/tmp/docker-nocreds docker compose up -d vector"
  else
    DOCKER_CONFIG=/tmp/docker-nocreds run_cmd /bin/bash -lc "docker compose up -d vector"
  fi
fi

echo "[4/6] Running real-host cutover checks..."
run_cmd "${cutover_cmd[@]}"

if [[ "${SKIP_POLICY_CHECK}" == "true" ]]; then
  echo "[5/6] Skipping endpoint policy drift check (--skip-policy-check)."
else
  echo "[5/6] Running endpoint policy drift check..."
  policy_cmd=(./scripts/endpoint-policy-drift-check.sh --policy-file "${POLICY_FILE}" --only-id "${ENDPOINT_ID}")
  if [[ "${POLICY_SOFT_FAIL}" == "true" ]]; then
    policy_cmd+=(--soft-fail)
  fi
  run_cmd "${policy_cmd[@]}"
fi

if [[ "${PROMOTE_REQUIRED_ON_SUCCESS}" == "true" ]]; then
  echo "[6/6] Promoting endpoint policy to required and verifying hard-fail enforcement..."
  promote_cmd=(
    ./scripts/upsert-endpoint-policy.sh
    --policy-file "${POLICY_FILE}"
    --id "${ENDPOINT_ID}"
    --computer "${COMPUTER}"
    --required true
    --max-stale-minutes "${PROMOTION_MAX_STALE_MINUTES}"
  )
  run_cmd "${promote_cmd[@]}"

  enforce_cmd=(
    ./scripts/endpoint-policy-drift-check.sh
    --policy-file "${POLICY_FILE}"
    --only-id "${ENDPOINT_ID}"
  )
  run_cmd "${enforce_cmd[@]}"
else
  echo "[6/6] Skipping policy promotion (use --promote-required-on-success or --first-real-host)."
fi

echo
echo "Cutover workflow completed."
echo "Copy endpoint bundle from:"
echo "  ${OUTPUT_DIR}/${ENDPOINT_ID}"
