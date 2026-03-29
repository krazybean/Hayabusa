#!/bin/sh
set -eu

RULE_DIR="${RULE_DIR:-/etc/hayabusa/rules}"
CLICKHOUSE_URL="${CLICKHOUSE_URL:-http://clickhouse:8123/}"
DETECTION_POLL_SECONDS="${DETECTION_POLL_SECONDS:-30}"
HEARTBEAT_FILE="${HEARTBEAT_FILE:-/tmp/detection-heartbeat}"

log() {
  printf '%s [detection] %s\n' "$(date -u +"%Y-%m-%dT%H:%M:%SZ")" "$*"
}

query_clickhouse() {
  sql="$1"
  if output="$(curl -fsS "${CLICKHOUSE_URL}" --data-binary "${sql}")"; then
    printf '%s' "${output}"
    return 0
  fi

  compact_sql="$(printf '%s' "${sql}" | tr '\n' ' ' | sed -E 's/[[:space:]]+/ /g')"
  log "ClickHouse query failed. sql=${compact_sql}"
  return 1
}

yaml_value() {
  file="$1"
  key="$2"
  awk -F': *' -v key="${key}" '
    $1 == key {
      sub($1 FS, "", $0)
      gsub(/^["'"'"']|["'"'"']$/, "", $0)
      print $0
      exit
    }
  ' "${file}"
}

yaml_query_block() {
  file="$1"
  awk '
    /^query:[[:space:]]*\|[[:space:]]*$/ { in_query=1; next }
    in_query == 1 {
      if ($0 ~ /^  /) {
        sub(/^  /, "", $0)
        print $0
        next
      }
      in_query=0
    }
  ' "${file}"
}

escape_sql_string() {
  printf '%s' "$1" | sed "s/'/''/g"
}

is_integer() {
  echo "$1" | grep -Eq '^[0-9]+$'
}

normalize_csv_list() {
  value="$1"
  printf '%s' "${value}" \
    | tr ',' '\n' \
    | sed -E 's/^[[:space:]]+//; s/[[:space:]]+$//' \
    | tr '[:upper:]' '[:lower:]' \
    | sed '/^$/d' \
    | awk '!seen[$0]++'
}

to_sql_string_list() {
  lines="$1"
  out=""
  while IFS= read -r item; do
    [ -n "${item}" ] || continue
    escaped_item="$(escape_sql_string "${item}")"
    if [ -n "${out}" ]; then
      out="${out}, "
    fi
    out="${out}'${escaped_item}'"
  done <<EOF
${lines}
EOF
  printf '%s' "${out}"
}

build_suppression_condition() {
  computers_csv="$1"
  users_csv="$2"
  computer_expr="$3"
  user_expr="$4"

  condition=""
  normalized_computers="$(normalize_csv_list "${computers_csv}")"
  normalized_users="$(normalize_csv_list "${users_csv}")"

  if [ -n "${normalized_computers}" ]; then
    computer_values="$(to_sql_string_list "${normalized_computers}")"
    if [ -n "${computer_values}" ]; then
      condition="${computer_expr} NOT IN (${computer_values})"
    fi
  fi

  if [ -n "${normalized_users}" ]; then
    user_values="$(to_sql_string_list "${normalized_users}")"
    if [ -n "${user_values}" ]; then
      user_condition="${user_expr} NOT IN (${user_values})"
      if [ -n "${condition}" ]; then
        condition="${condition} AND ${user_condition}"
      else
        condition="${user_condition}"
      fi
    fi
  fi

  if [ -z "${condition}" ]; then
    condition="1 = 1"
  fi

  printf '%s' "${condition}"
}

apply_suppression_condition() {
  query="$1"
  condition="$2"
  escaped_condition="$(printf '%s' "${condition}" | sed -e 's/[\/&]/\\&/g')"
  printf '%s' "${query}" | sed "s/{{SUPPRESSION_CONDITION}}/${escaped_condition}/g"
}

rule_recently_triggered() {
  rule_id="$1"
  cooldown_seconds="$2"

  if [ "${cooldown_seconds}" -le 0 ]; then
    return 1
  fi

  recent_count="$(query_clickhouse "SELECT count() FROM security.alert_candidates WHERE rule_id = '${rule_id}' AND ts > now() - INTERVAL ${cooldown_seconds} SECOND FORMAT TabSeparated" | tr -d '\r\n')"
  if is_integer "${recent_count}" && [ "${recent_count}" -gt 0 ]; then
    return 0
  fi

  return 1
}

normalize_query_for_exec() {
  # Strip a trailing semicolon and append a deterministic output format.
  printf '%s' "$1" | sed -E 's/[[:space:]]*;[[:space:]]*$//'
}

ensure_schema() {
  query_clickhouse "
CREATE TABLE IF NOT EXISTS security.alert_candidates
(
    ts              DateTime64(3, 'UTC') DEFAULT now64(3),
    rule_id         String,
    rule_name       String,
    severity        LowCardinality(String),
    hits            UInt64,
    threshold_op    LowCardinality(String),
    threshold_value UInt64,
    query           String,
    details         String
)
ENGINE = MergeTree()
PARTITION BY toYYYYMM(ts)
ORDER BY (ts, rule_id)
TTL ts + INTERVAL 30 DAY;
" >/dev/null
}

evaluate_threshold() {
  hits="$1"
  op="$2"
  threshold="$3"

  case "${op}" in
    gt)  [ "${hits}" -gt "${threshold}" ] ;;
    gte) [ "${hits}" -ge "${threshold}" ] ;;
    eq)  [ "${hits}" -eq "${threshold}" ] ;;
    lt)  [ "${hits}" -lt "${threshold}" ] ;;
    lte) [ "${hits}" -le "${threshold}" ] ;;
    *)
      log "Unsupported threshold_op=${op}; expected one of gt,gte,eq,lt,lte."
      return 1
      ;;
  esac
}

run_rule() {
  rule_file="$1"

  rule_id="$(yaml_value "${rule_file}" "id")"
  rule_name="$(yaml_value "${rule_file}" "name")"
  severity="$(yaml_value "${rule_file}" "severity")"
  enabled="$(yaml_value "${rule_file}" "enabled")"
  threshold_op="$(yaml_value "${rule_file}" "threshold_op")"
  threshold_value="$(yaml_value "${rule_file}" "threshold_value")"
  cooldown_seconds="$(yaml_value "${rule_file}" "cooldown_seconds")"
  suppression_computers_csv="$(yaml_value "${rule_file}" "suppression_computers_csv")"
  suppression_users_csv="$(yaml_value "${rule_file}" "suppression_users_csv")"
  suppression_computer_expr="$(yaml_value "${rule_file}" "suppression_computer_expr")"
  suppression_user_expr="$(yaml_value "${rule_file}" "suppression_user_expr")"
  query_block="$(yaml_query_block "${rule_file}")"

  [ -n "${rule_id}" ] || { log "Skipping ${rule_file}: missing id"; return 0; }
  [ -n "${rule_name}" ] || { log "Skipping ${rule_file}: missing name"; return 0; }
  [ -n "${severity}" ] || severity="medium"
  [ -n "${enabled}" ] || enabled="false"
  [ -n "${threshold_op}" ] || threshold_op="gte"
  [ -n "${threshold_value}" ] || threshold_value="1"
  [ -n "${cooldown_seconds}" ] || cooldown_seconds="0"
  [ -n "${suppression_computer_expr}" ] || suppression_computer_expr="lowerUTF8(ifNull(fields['computer'], ifNull(fields['hostname'], '')))"
  [ -n "${suppression_user_expr}" ] || suppression_user_expr="lowerUTF8(ifNull(fields['user'], ifNull(fields['username'], ifNull(fields['subject_user_name'], ifNull(fields['target_user_name'], '')))))"

  if [ "${enabled}" != "true" ]; then
    return 0
  fi

  if [ -z "${query_block}" ]; then
    log "Skipping ${rule_id}: missing query block"
    return 0
  fi

  if ! is_integer "${threshold_value}"; then
    log "Skipping ${rule_id}: threshold_value must be integer"
    return 0
  fi

  if ! is_integer "${cooldown_seconds}"; then
    log "Skipping ${rule_id}: cooldown_seconds must be integer"
    return 0
  fi

  exec_query="$(normalize_query_for_exec "${query_block}")"
  suppression_condition="$(build_suppression_condition "${suppression_computers_csv}" "${suppression_users_csv}" "${suppression_computer_expr}" "${suppression_user_expr}")"

  if ( [ -n "${suppression_computers_csv}" ] || [ -n "${suppression_users_csv}" ] ) && ! printf '%s' "${exec_query}" | grep -q "{{SUPPRESSION_CONDITION}}"; then
    log "Rule ${rule_id} defines suppression_* values but query has no {{SUPPRESSION_CONDITION}} placeholder; suppressions will not apply."
  fi

  exec_query="$(apply_suppression_condition "${exec_query}" "${suppression_condition}")"
  hits_raw="$(query_clickhouse "${exec_query} FORMAT TabSeparated" | head -n1 | tr -d '\r' | awk '{print $1}')"

  if ! is_integer "${hits_raw}"; then
    log "Rule ${rule_id} returned non-integer result: ${hits_raw}"
    return 0
  fi

  if evaluate_threshold "${hits_raw}" "${threshold_op}" "${threshold_value}"; then
    if rule_recently_triggered "${rule_id}" "${cooldown_seconds}"; then
      log "Suppressed rule=${rule_id} due to cooldown_seconds=${cooldown_seconds}"
      return 0
    fi

    query_compact="$(printf '%s' "${exec_query}" | tr '\n' ' ' | sed -E 's/[[:space:]]+/ /g')"
    escaped_name="$(escape_sql_string "${rule_name}")"
    escaped_query="$(escape_sql_string "${query_compact}")"
    escaped_severity="$(escape_sql_string "${severity}")"
    escaped_op="$(escape_sql_string "${threshold_op}")"

    query_clickhouse "
INSERT INTO security.alert_candidates
  (rule_id, rule_name, severity, hits, threshold_op, threshold_value, query, details)
VALUES
  (
    '${rule_id}',
    '${escaped_name}',
    '${escaped_severity}',
    ${hits_raw},
    '${escaped_op}',
    ${threshold_value},
    '${escaped_query}',
    'Triggered by Hayabusa detection service'
  );
" >/dev/null
    log "Triggered rule=${rule_id} hits=${hits_raw} op=${threshold_op} threshold=${threshold_value}"
  fi
}

main() {
  ensure_schema
  log "Detection service started. polling=${DETECTION_POLL_SECONDS}s rules=${RULE_DIR}"

  while :; do
    found=0
    for rule_file in "${RULE_DIR}"/*.yaml; do
      if [ -f "${rule_file}" ]; then
        found=1
        run_rule "${rule_file}" || true
      fi
    done
    if [ "${found}" -eq 0 ]; then
      log "No rule files found in ${RULE_DIR}"
    fi

    date -u +"%Y-%m-%dT%H:%M:%SZ" > "${HEARTBEAT_FILE}"
    sleep "${DETECTION_POLL_SECONDS}"
  done
}

main
