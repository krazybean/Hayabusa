#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "${ROOT_DIR}"

POLICY_FILE="${ENDPOINT_POLICY_FILE:-${ROOT_DIR}/configs/endpoints/windows-endpoints.yaml}"
CLICKHOUSE_URL="${ENDPOINT_POLICY_CLICKHOUSE_URL:-http://localhost:8123/}"
SOFT_FAIL=false
ONLY_ID=""

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
    false|no|0|off|"") printf "false" ;;
    *)
      echo "ERROR: invalid boolean value: $1" >&2
      exit 1
      ;;
  esac
}

usage() {
  cat <<'EOF'
Usage:
  ./scripts/endpoint-policy-drift-check.sh [options]

Options:
  --policy-file <path>   Endpoint policy YAML (default: configs/endpoints/windows-endpoints.yaml)
  --clickhouse-url <url> ClickHouse HTTP URL (default: http://localhost:8123/)
  --only-id <id>         Evaluate only one policy endpoint id
  --soft-fail            Exit 0 even when required-policy drift is found
  -h, --help             Show this help
EOF
}

while [[ $# -gt 0 ]]; do
  case "$1" in
    --policy-file)
      POLICY_FILE="${2:-}"
      shift 2
      ;;
    --clickhouse-url)
      CLICKHOUSE_URL="${2:-}"
      shift 2
      ;;
    --only-id)
      ONLY_ID="${2:-}"
      shift 2
      ;;
    --soft-fail)
      SOFT_FAIL=true
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

if [[ ! -f "${POLICY_FILE}" ]]; then
  echo "ERROR: policy file not found: ${POLICY_FILE}" >&2
  exit 1
fi

if [[ -n "${ONLY_ID}" && ! "${ONLY_ID}" =~ ^[A-Za-z0-9._:-]+$ ]]; then
  echo "ERROR: --only-id contains unsupported characters." >&2
  exit 1
fi

run_clickhouse_query() {
  local query="$1"
  local output

  if output="$(curl -fsS "${CLICKHOUSE_URL}" --data-binary "${query}" 2>/dev/null)"; then
    printf "%s" "${output}"
    return 0
  fi

  docker compose exec -T clickhouse clickhouse-client --query "${query}"
}

default_lane="vector-windows-endpoint"
default_max_stale_minutes="120"
default_required="false"

endpoint_ids=()
endpoint_computers=()
endpoint_lanes=()
endpoint_max_stales=()
endpoint_requireds=()

current_id=""
current_computer=""
current_lane=""
current_max_stale=""
current_required=""

append_endpoint() {
  if [[ -z "${current_id}" ]]; then
    return
  fi

  local resolved_computer="${current_computer:-${current_id}}"
  local resolved_lane="${current_lane:-${default_lane}}"
  local resolved_max_stale="${current_max_stale:-${default_max_stale_minutes}}"
  local resolved_required="${current_required:-${default_required}}"

  resolved_required="$(normalize_bool "${resolved_required}")"

  if [[ ! "${current_id}" =~ ^[A-Za-z0-9._:-]+$ ]]; then
    echo "ERROR: endpoint id has unsupported characters: ${current_id}" >&2
    exit 1
  fi
  if [[ ! "${resolved_computer}" =~ ^[A-Za-z0-9._:-]+$ ]]; then
    echo "ERROR: endpoint computer has unsupported characters: ${resolved_computer}" >&2
    exit 1
  fi
  if [[ ! "${resolved_lane}" =~ ^[A-Za-z0-9._:-]+$ ]]; then
    echo "ERROR: endpoint lane has unsupported characters: ${resolved_lane}" >&2
    exit 1
  fi
  if [[ ! "${resolved_max_stale}" =~ ^[0-9]+$ ]]; then
    echo "ERROR: endpoint max_stale_minutes must be integer for id=${current_id}" >&2
    exit 1
  fi

  endpoint_ids+=("${current_id}")
  endpoint_computers+=("${resolved_computer}")
  endpoint_lanes+=("${resolved_lane}")
  endpoint_max_stales+=("${resolved_max_stale}")
  endpoint_requireds+=("${resolved_required}")

  current_id=""
  current_computer=""
  current_lane=""
  current_max_stale=""
  current_required=""
}

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
        required) default_required="${value}" ;;
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
      esac
    fi
  fi
done < "${POLICY_FILE}"

append_endpoint

if [[ "${#endpoint_ids[@]}" -eq 0 ]]; then
  echo "ERROR: no endpoints found in policy file ${POLICY_FILE}" >&2
  exit 1
fi

ok_count=0
optional_missing_count=0
optional_stale_count=0
drift_count=0
evaluated_count=0
matched_only_id=false

printf "Endpoint policy file: %s\n" "${POLICY_FILE}"
printf "ClickHouse URL: %s\n" "${CLICKHOUSE_URL}"
echo

for i in "${!endpoint_ids[@]}"; do
  endpoint_id="${endpoint_ids[$i]}"
  computer="${endpoint_computers[$i]}"
  lane="${endpoint_lanes[$i]}"
  max_stale="${endpoint_max_stales[$i]}"
  required="${endpoint_requireds[$i]}"

  if [[ -n "${ONLY_ID}" && "${ONLY_ID}" != "${endpoint_id}" ]]; then
    continue
  fi
  if [[ -n "${ONLY_ID}" && "${ONLY_ID}" == "${endpoint_id}" ]]; then
    matched_only_id=true
  fi

  evaluated_count=$((evaluated_count + 1))

  snapshot_query="SELECT count(), ifNull(toInt64(any(minutes_since_last_seen)), -1), ifNull(any(status), 'missing'), ifNull(toUInt64(any(total_events)), 0), ifNull(toString(any(last_seen)), '') FROM security.endpoint_activity WHERE endpoint_id='${computer}' AND lane='${lane}' FORMAT TabSeparated"
  snapshot_row="$(run_clickhouse_query "${snapshot_query}" | tr -d '\r\n')"

  observed_count=""
  observed_minutes=""
  observed_status=""
  observed_events=""
  observed_last_seen=""
  IFS=$'\t' read -r observed_count observed_minutes observed_status observed_events observed_last_seen <<< "${snapshot_row}"

  if [[ ! "${observed_count}" =~ ^[0-9]+$ ]]; then
    echo "ERROR: unexpected endpoint snapshot response for id=${endpoint_id}: ${snapshot_row}" >&2
    exit 1
  fi

  if (( observed_count == 0 )); then
    lanes_query="SELECT arrayStringConcat(groupArray(lane), ',') FROM security.endpoint_activity WHERE endpoint_id='${computer}' FORMAT TabSeparated"
    observed_lanes="$(run_clickhouse_query "${lanes_query}" | tr -d '\r\n')"

    if [[ "${required}" == "true" ]]; then
      if [[ -n "${observed_lanes}" ]]; then
        echo "DRIFT lane-mismatch: id=${endpoint_id} computer=${computer} expected_lane=${lane} observed_lanes=${observed_lanes}"
      else
        echo "DRIFT missing: id=${endpoint_id} computer=${computer} expected_lane=${lane}"
      fi
      drift_count=$((drift_count + 1))
    else
      echo "WARN optional-missing: id=${endpoint_id} computer=${computer} lane=${lane}"
      optional_missing_count=$((optional_missing_count + 1))
    fi
    continue
  fi

  if [[ ! "${observed_minutes}" =~ ^-?[0-9]+$ ]]; then
    echo "ERROR: unexpected minutes_since_last_seen for id=${endpoint_id}: ${observed_minutes}" >&2
    exit 1
  fi

  if (( observed_minutes > max_stale )); then
    if [[ "${required}" == "true" ]]; then
      echo "DRIFT stale: id=${endpoint_id} computer=${computer} lane=${lane} minutes_since_last_seen=${observed_minutes} max_stale_minutes=${max_stale} status=${observed_status}"
      drift_count=$((drift_count + 1))
    else
      echo "WARN optional-stale: id=${endpoint_id} computer=${computer} lane=${lane} minutes_since_last_seen=${observed_minutes} max_stale_minutes=${max_stale} status=${observed_status}"
      optional_stale_count=$((optional_stale_count + 1))
    fi
    continue
  fi

  echo "OK: id=${endpoint_id} computer=${computer} lane=${lane} status=${observed_status} minutes_since_last_seen=${observed_minutes} events=${observed_events} last_seen=${observed_last_seen}"
  ok_count=$((ok_count + 1))
done

if [[ -n "${ONLY_ID}" && "${matched_only_id}" != "true" ]]; then
  echo "ERROR: --only-id value not present in policy file: ${ONLY_ID}" >&2
  exit 1
fi

if (( evaluated_count == 0 )); then
  echo "ERROR: no endpoints evaluated from policy file ${POLICY_FILE}" >&2
  exit 1
fi

echo
echo "Summary: evaluated=${evaluated_count} ok=${ok_count} optional_missing=${optional_missing_count} optional_stale=${optional_stale_count} drift=${drift_count}"

if (( drift_count > 0 )); then
  if [[ "${SOFT_FAIL}" == "true" ]]; then
    echo "Policy drift detected, but soft-fail enabled."
    exit 0
  fi
  echo "Policy drift detected."
  exit 1
fi

echo "Policy drift check passed."
