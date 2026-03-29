#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
VECTOR_CONFIG="${WINDOWS_PERMIT_VECTOR_CONFIG:-${ROOT_DIR}/configs/vector/vector.yaml}"
INCLUDE_LOOPBACK=false
DRY_RUN=false
CIDRS=()

usage() {
  cat <<'EOF'
Usage:
  ./scripts/set-windows-permit-origin.sh --cidr <cidr> [--cidr <cidr> ...] [options]

Options:
  --cidr <cidr>          CIDR to allow for Windows forward input (repeatable)
  --include-loopback     Keep 127.0.0.0/8 for local validation flows
  --dry-run              Print resulting file to stdout without writing
  --config <path>        Vector config path (default: configs/vector/vector.yaml)
  -h, --help             Show this help
EOF
}

while [[ $# -gt 0 ]]; do
  case "$1" in
    --cidr)
      if [[ $# -lt 2 || -z "${2:-}" ]]; then
        echo "ERROR: --cidr requires a non-empty value." >&2
        exit 1
      fi
      CIDRS+=("${2}")
      shift 2
      ;;
    --include-loopback)
      INCLUDE_LOOPBACK=true
      shift
      ;;
    --dry-run)
      DRY_RUN=true
      shift
      ;;
    --config)
      if [[ $# -lt 2 || -z "${2:-}" ]]; then
        echo "ERROR: --config requires a path value." >&2
        exit 1
      fi
      VECTOR_CONFIG="${2}"
      shift 2
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

if [[ "${#CIDRS[@]}" -eq 0 ]]; then
  echo "ERROR: at least one --cidr is required." >&2
  usage
  exit 1
fi

if [[ ! -f "${VECTOR_CONFIG}" ]]; then
  echo "ERROR: config file not found: ${VECTOR_CONFIG}" >&2
  exit 1
fi

for cidr in "${CIDRS[@]}"; do
  if [[ -z "${cidr}" ]]; then
    echo "ERROR: empty CIDR value is not allowed." >&2
    exit 1
  fi
done

if [[ "${INCLUDE_LOOPBACK}" == "true" ]]; then
  CIDRS+=("127.0.0.0/8")
fi

# Deduplicate CIDRs while preserving order.
DEDUPED_CIDRS=()
for cidr in "${CIDRS[@]}"; do
  seen=false
  if [[ "${#DEDUPED_CIDRS[@]}" -gt 0 ]]; then
    for existing in "${DEDUPED_CIDRS[@]}"; do
      if [[ "${existing}" == "${cidr}" ]]; then
        seen=true
        break
      fi
    done
  fi
  if [[ "${seen}" == "false" ]]; then
    DEDUPED_CIDRS+=("${cidr}")
  fi
done

tmp_output="$(mktemp)"
trap 'rm -f "${tmp_output}"' EXIT

CIDR_LINES=""
for cidr in "${DEDUPED_CIDRS[@]}"; do
  CIDR_LINES="${CIDR_LINES}      - ${cidr}\n"
done

awk -v cidr_lines="${CIDR_LINES}" '
  BEGIN {
    in_windows = 0
    replacing = 0
    replaced = 0
    line_count = split(cidr_lines, lines, "\n")
  }
  /^  ingest_fluent_windows_forward:$/ {
    in_windows = 1
    print
    next
  }
  in_windows && /^    permit_origin:$/ {
    print
    for (i = 1; i <= line_count; i++) {
      if (lines[i] != "") print lines[i]
    }
    replacing = 1
    replaced = 1
    next
  }
  replacing {
    if ($0 ~ /^      - /) {
      next
    }
    replacing = 0
  }
  in_windows && /^  [^ ]/ {
    in_windows = 0
  }
  { print }
  END {
    if (replaced == 0) {
      exit 42
    }
  }
' "${VECTOR_CONFIG}" > "${tmp_output}" || {
  status=$?
  if [[ "${status}" -eq 42 ]]; then
    echo "ERROR: could not locate permit_origin under ingest_fluent_windows_forward in ${VECTOR_CONFIG}" >&2
  fi
  exit "${status}"
}

if [[ "${DRY_RUN}" == "true" ]]; then
  cat "${tmp_output}"
  exit 0
fi

cp "${tmp_output}" "${VECTOR_CONFIG}"

echo "Updated Windows permit_origin in ${VECTOR_CONFIG}:"
for cidr in "${DEDUPED_CIDRS[@]}"; do
  echo "  - ${cidr}"
done
