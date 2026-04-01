#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "${ROOT_DIR}"

POLICY_FILE="${ENDPOINT_POLICY_FILE:-${ROOT_DIR}/configs/endpoints/windows-endpoints.yaml}"
ENDPOINT_ID=""
COMPUTER=""
LANE=""
MAX_STALE_MINUTES=""
REQUIRED=""
OWNER=""
NOTES=""

trim() {
  local value="$1"
  value="${value#"${value%%[![:space:]]*}"}"
  value="${value%"${value##*[![:space:]]}"}"
  printf "%s" "${value}"
}

normalize_scalar() {
  local value
  value="$(trim "$1")"
  if [[ "${value}" == \"*\" ]]; then
    value="${value#\"}"
    value="${value%\"}"
  elif [[ "${value}" == \'*\' ]]; then
    value="${value#\'}"
    value="${value%\'}"
  fi
  printf "%s" "${value}"
}

normalize_bool() {
  local value
  value="$(printf "%s" "$1" | tr '[:upper:]' '[:lower:]')"
  case "${value}" in
    true|yes|1|on) printf "true" ;;
    false|no|0|off) printf "false" ;;
    *)
      echo "ERROR: invalid boolean value: $1" >&2
      exit 1
      ;;
  esac
}

yaml_quote() {
  local value="$1"
  value="${value//\\/\\\\}"
  value="${value//\"/\\\"}"
  printf "\"%s\"" "${value}"
}

usage() {
  cat <<'EOF'
Usage:
  ./scripts/upsert-endpoint-policy.sh --id <endpoint-id> [options]

Options:
  --id <value>                 Endpoint policy ID (required)
  --computer <value>           Endpoint computer identity
  --lane <value>               Expected ingest lane
  --max-stale-minutes <n>      Endpoint stale threshold (minutes)
  --required <true|false>      Required endpoint enforcement toggle
  --owner <value>              Optional owner metadata
  --notes <value>              Optional notes metadata
  --policy-file <path>         Policy file path (default: configs/endpoints/windows-endpoints.yaml)
  -h, --help                   Show this help
EOF
}

while [[ $# -gt 0 ]]; do
  case "$1" in
    --id)
      ENDPOINT_ID="${2:-}"
      shift 2
      ;;
    --computer)
      COMPUTER="${2:-}"
      shift 2
      ;;
    --lane)
      LANE="${2:-}"
      shift 2
      ;;
    --max-stale-minutes)
      MAX_STALE_MINUTES="${2:-}"
      shift 2
      ;;
    --required)
      REQUIRED="${2:-}"
      shift 2
      ;;
    --owner)
      OWNER="${2:-}"
      shift 2
      ;;
    --notes)
      NOTES="${2:-}"
      shift 2
      ;;
    --policy-file)
      POLICY_FILE="${2:-}"
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

if [[ -z "${ENDPOINT_ID}" ]]; then
  usage
  exit 1
fi

if [[ ! "${ENDPOINT_ID}" =~ ^[A-Za-z0-9._:-]+$ ]]; then
  echo "ERROR: --id contains unsupported characters: ${ENDPOINT_ID}" >&2
  exit 1
fi

if [[ -n "${COMPUTER}" && ! "${COMPUTER}" =~ ^[A-Za-z0-9._:-]+$ ]]; then
  echo "ERROR: --computer contains unsupported characters: ${COMPUTER}" >&2
  exit 1
fi

if [[ -n "${LANE}" && ! "${LANE}" =~ ^[A-Za-z0-9._:-]+$ ]]; then
  echo "ERROR: --lane contains unsupported characters: ${LANE}" >&2
  exit 1
fi

if [[ -n "${MAX_STALE_MINUTES}" && ! "${MAX_STALE_MINUTES}" =~ ^[0-9]+$ ]]; then
  echo "ERROR: --max-stale-minutes must be an integer." >&2
  exit 1
fi

if [[ -n "${REQUIRED}" ]]; then
  REQUIRED="$(normalize_bool "${REQUIRED}")"
fi

if [[ -n "${OWNER}" && ! "${OWNER}" =~ ^[A-Za-z0-9._:@/-]+$ ]]; then
  echo "ERROR: --owner contains unsupported characters: ${OWNER}" >&2
  exit 1
fi

mkdir -p "$(dirname "${POLICY_FILE}")"

default_lane="vector-windows-endpoint"
default_max_stale_minutes="120"
default_required="false"

endpoint_ids=()
endpoint_computers=()
endpoint_lanes=()
endpoint_max_stales=()
endpoint_requireds=()
endpoint_owners=()
endpoint_notes=()

current_id=""
current_computer=""
current_lane=""
current_max_stale=""
current_required=""
current_owner=""
current_notes=""

append_endpoint() {
  if [[ -z "${current_id}" ]]; then
    return
  fi

  local resolved_computer="${current_computer:-${current_id}}"
  local resolved_lane="${current_lane:-${default_lane}}"
  local resolved_max_stale="${current_max_stale:-${default_max_stale_minutes}}"
  local resolved_required="${current_required:-${default_required}}"

  resolved_required="$(normalize_bool "${resolved_required}")"

  endpoint_ids+=("${current_id}")
  endpoint_computers+=("${resolved_computer}")
  endpoint_lanes+=("${resolved_lane}")
  endpoint_max_stales+=("${resolved_max_stale}")
  endpoint_requireds+=("${resolved_required}")
  endpoint_owners+=("${current_owner}")
  endpoint_notes+=("${current_notes}")

  current_id=""
  current_computer=""
  current_lane=""
  current_max_stale=""
  current_required=""
  current_owner=""
  current_notes=""
}

if [[ -f "${POLICY_FILE}" ]]; then
  in_defaults=false
  in_endpoints=false

  while IFS= read -r raw_line || [[ -n "${raw_line}" ]]; do
    line="${raw_line%%#*}"
    line="$(trim "${line}")"
    [[ -z "${line}" ]] && continue

    if [[ "${line}" == "defaults:" ]]; then
      in_defaults=true
      in_endpoints=false
      continue
    fi
    if [[ "${line}" == "endpoints:" ]]; then
      append_endpoint
      in_defaults=false
      in_endpoints=true
      continue
    fi

    if [[ "${in_defaults}" == "true" ]]; then
      if [[ "${line}" =~ ^([a-z_]+):[[:space:]]*(.+)$ ]]; then
        key="${BASH_REMATCH[1]}"
        value="$(normalize_scalar "${BASH_REMATCH[2]}")"
        case "${key}" in
          lane) default_lane="${value}" ;;
          max_stale_minutes) default_max_stale_minutes="${value}" ;;
          required) default_required="$(normalize_bool "${value}")" ;;
        esac
      fi
      continue
    fi

    if [[ "${in_endpoints}" == "true" ]]; then
      if [[ "${line}" =~ ^-[[:space:]]*id:[[:space:]]*(.+)$ ]]; then
        append_endpoint
        current_id="$(normalize_scalar "${BASH_REMATCH[1]}")"
        continue
      fi

      if [[ "${line}" =~ ^([a-z_]+):[[:space:]]*(.+)$ ]]; then
        key="${BASH_REMATCH[1]}"
        value="$(normalize_scalar "${BASH_REMATCH[2]}")"
        case "${key}" in
          computer) current_computer="${value}" ;;
          lane) current_lane="${value}" ;;
          max_stale_minutes) current_max_stale="${value}" ;;
          required) current_required="${value}" ;;
          owner) current_owner="${value}" ;;
          notes) current_notes="${value}" ;;
        esac
      fi
    fi
  done < "${POLICY_FILE}"

  append_endpoint
fi

target_index=-1
for i in "${!endpoint_ids[@]}"; do
  if [[ "${endpoint_ids[$i]}" == "${ENDPOINT_ID}" ]]; then
    target_index="${i}"
    break
  fi
done

if (( target_index < 0 )); then
  endpoint_ids+=("${ENDPOINT_ID}")
  endpoint_computers+=("${ENDPOINT_ID}")
  endpoint_lanes+=("${default_lane}")
  endpoint_max_stales+=("${default_max_stale_minutes}")
  endpoint_requireds+=("${default_required}")
  endpoint_owners+=("")
  endpoint_notes+=("")
  target_index=$(( ${#endpoint_ids[@]} - 1 ))
fi

if [[ -n "${COMPUTER}" ]]; then endpoint_computers[$target_index]="${COMPUTER}"; fi
if [[ -n "${LANE}" ]]; then endpoint_lanes[$target_index]="${LANE}"; fi
if [[ -n "${MAX_STALE_MINUTES}" ]]; then endpoint_max_stales[$target_index]="${MAX_STALE_MINUTES}"; fi
if [[ -n "${REQUIRED}" ]]; then endpoint_requireds[$target_index]="${REQUIRED}"; fi
if [[ -n "${OWNER}" ]]; then endpoint_owners[$target_index]="${OWNER}"; fi
if [[ -n "${NOTES}" ]]; then endpoint_notes[$target_index]="${NOTES}"; fi

for i in "${!endpoint_ids[@]}"; do
  if [[ ! "${endpoint_ids[$i]}" =~ ^[A-Za-z0-9._:-]+$ ]]; then
    echo "ERROR: endpoint id has unsupported characters: ${endpoint_ids[$i]}" >&2
    exit 1
  fi
  if [[ ! "${endpoint_computers[$i]}" =~ ^[A-Za-z0-9._:-]+$ ]]; then
    echo "ERROR: endpoint computer has unsupported characters: ${endpoint_computers[$i]}" >&2
    exit 1
  fi
  if [[ ! "${endpoint_lanes[$i]}" =~ ^[A-Za-z0-9._:-]+$ ]]; then
    echo "ERROR: endpoint lane has unsupported characters: ${endpoint_lanes[$i]}" >&2
    exit 1
  fi
  if [[ ! "${endpoint_max_stales[$i]}" =~ ^[0-9]+$ ]]; then
    echo "ERROR: endpoint max_stale_minutes must be integer for id=${endpoint_ids[$i]}" >&2
    exit 1
  fi
  endpoint_requireds[$i]="$(normalize_bool "${endpoint_requireds[$i]}")"
done

tmp_file="$(mktemp)"
cleanup() {
  rm -f "${tmp_file}"
}
trap cleanup EXIT

{
  echo "defaults:"
  printf "  lane: %s\n" "${default_lane}"
  printf "  max_stale_minutes: %s\n" "${default_max_stale_minutes}"
  printf "  required: %s\n" "${default_required}"
  echo
  echo "endpoints:"
  for i in "${!endpoint_ids[@]}"; do
    printf "  - id: %s\n" "${endpoint_ids[$i]}"
    printf "    computer: %s\n" "${endpoint_computers[$i]}"
    printf "    lane: %s\n" "${endpoint_lanes[$i]}"
    printf "    max_stale_minutes: %s\n" "${endpoint_max_stales[$i]}"
    printf "    required: %s\n" "${endpoint_requireds[$i]}"
    if [[ -n "${endpoint_owners[$i]}" ]]; then
      printf "    owner: %s\n" "$(yaml_quote "${endpoint_owners[$i]}")"
    fi
    if [[ -n "${endpoint_notes[$i]}" ]]; then
      printf "    notes: %s\n" "$(yaml_quote "${endpoint_notes[$i]}")"
    fi
  done
} > "${tmp_file}"

mv "${tmp_file}" "${POLICY_FILE}"

printf "Upserted endpoint policy entry:\n"
printf "  policy_file=%s\n" "${POLICY_FILE}"
printf "  id=%s\n" "${endpoint_ids[$target_index]}"
printf "  computer=%s\n" "${endpoint_computers[$target_index]}"
printf "  lane=%s\n" "${endpoint_lanes[$target_index]}"
printf "  max_stale_minutes=%s\n" "${endpoint_max_stales[$target_index]}"
printf "  required=%s\n" "${endpoint_requireds[$target_index]}"
