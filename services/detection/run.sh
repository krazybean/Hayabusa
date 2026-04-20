#!/bin/sh
set -eu

RULE_DIR="${RULE_DIR:-/etc/hayabusa/rules}"
RULE_SQL_DIR="${RULE_SQL_DIR:-/etc/hayabusa/detections/rules}"
RULE_METADATA_DIR="${RULE_METADATA_DIR:-/etc/hayabusa/detections/metadata}"
RULE_REGISTRY_LOADER="${RULE_REGISTRY_LOADER:-/app/load-detection-rules.sh}"
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

build_alert_fingerprint() {
  alert_type="$1"
  principal="$2"
  source_ip="$3"
  endpoint_id="$4"
  source_kind="$5"
  window_bucket="$6"

  # Fingerprints define "same alert" as the same alert type, entity tuple,
  # source kind, and stable window bucket rather than an exact first-seen time.
  printf '%s|%s|%s|%s|%s|%s' "${alert_type}" "${principal}" "${source_ip}" "${endpoint_id}" "${source_kind}" "${window_bucket}"
}

alert_recently_emitted() {
  alert_fingerprint="$1"
  cooldown_seconds="$2"

  if [ "${cooldown_seconds}" -le 0 ]; then
    return 1
  fi

  escaped_alert_fingerprint="$(escape_sql_string "${alert_fingerprint}")"
  recent_count="$(query_clickhouse "SELECT count() FROM security.alert_candidates WHERE alert_fingerprint = '${escaped_alert_fingerprint}' AND ts > now() - INTERVAL ${cooldown_seconds} SECOND FORMAT TabSeparated" | tr -d '\r\n')"
  if is_integer "${recent_count}" && [ "${recent_count}" -gt 0 ]; then
    return 0
  fi

  return 1
}

alert_already_recorded() {
  alert_fingerprint="$1"
  escaped_alert_fingerprint="$(escape_sql_string "${alert_fingerprint}")"

  existing_count="$(query_clickhouse "SELECT count() FROM security.alert_candidates WHERE alert_fingerprint = '${escaped_alert_fingerprint}' FORMAT TabSeparated" | tr -d '\r\n')"
  if is_integer "${existing_count}" && [ "${existing_count}" -gt 0 ]; then
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
    alert_type      LowCardinality(String) DEFAULT '',
    alert_fingerprint String DEFAULT '',
    severity        LowCardinality(String),
    hits            UInt64,
    attempt_count   UInt64 DEFAULT 0,
    principal       String DEFAULT '',
    entity_user     String DEFAULT '',
    source_ip       String DEFAULT '',
    entity_src_ip   String DEFAULT '',
    endpoint_id     String DEFAULT '',
    entity_host     String DEFAULT '',
    window_start    DateTime64(3, 'UTC') DEFAULT now64(3),
    first_seen_ts   DateTime64(3, 'UTC') DEFAULT now64(3),
    window_end      DateTime64(3, 'UTC') DEFAULT now64(3),
    last_seen_ts    DateTime64(3, 'UTC') DEFAULT now64(3),
    window_bucket   DateTime64(3, 'UTC') DEFAULT now64(3),
    distinct_user_count UInt64 DEFAULT 0,
    distinct_ip_count UInt64 DEFAULT 0,
    source_kind     LowCardinality(String) DEFAULT '',
    reason          String DEFAULT '',
    evidence_summary String DEFAULT '',
    workflow_state  LowCardinality(String) DEFAULT 'new',
    threshold_op    LowCardinality(String),
    threshold_value UInt64,
    query           String,
    details         String DEFAULT ''
)
ENGINE = MergeTree()
PARTITION BY toYYYYMM(ts)
ORDER BY (ts, rule_id)
TTL ts + INTERVAL 30 DAY;
" >/dev/null
}

replace_placeholder() {
  query="$1"
  placeholder="$2"
  value="$3"
  escaped_value="$(printf '%s' "${value}" | sed -e 's/[\/&]/\\&/g')"
  printf '%s' "${query}" | sed "s/{{${placeholder}}}/${escaped_value}/g"
}

apply_rule_placeholders() {
  query="$1"
  window_minutes="$2"
  threshold_attempts="$3"
  threshold_distinct_users="$4"
  threshold_distinct_ips="$5"
  threshold_failures="$6"

  query="$(replace_placeholder "${query}" "WINDOW_MINUTES" "${window_minutes}")"
  query="$(replace_placeholder "${query}" "THRESHOLD_ATTEMPTS" "${threshold_attempts}")"
  query="$(replace_placeholder "${query}" "THRESHOLD_DISTINCT_USERS" "${threshold_distinct_users}")"
  query="$(replace_placeholder "${query}" "THRESHOLD_DISTINCT_IPS" "${threshold_distinct_ips}")"
  query="$(replace_placeholder "${query}" "THRESHOLD_FAILURES" "${threshold_failures}")"
  printf '%s' "${query}"
}

tsv_column() {
  line="$1"
  column_index="$2"
  printf '%s' "${line}" | awk -F '\t' -v column_index="${column_index}" '{ print $column_index }'
}

default_context_timestamp() {
  date -u +"%Y-%m-%d %H:%M:%S.000"
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

find_rule_file_by_id() {
  target_rule_id="$1"
  for candidate_file in "${RULE_DIR}"/*.yaml; do
    [ -f "${candidate_file}" ] || continue
    candidate_rule_id="$(yaml_value "${candidate_file}" "id")"
    if [ "${candidate_rule_id}" = "${target_rule_id}" ]; then
      printf '%s' "${candidate_file}"
      return 0
    fi
  done
  return 1
}

list_enabled_sql_rules() {
  if [ -f "${RULE_REGISTRY_LOADER}" ]; then
    if output="$(
      RULE_SQL_DIR="${RULE_SQL_DIR}" \
      RULE_METADATA_DIR="${RULE_METADATA_DIR}" \
      /bin/sh "${RULE_REGISTRY_LOADER}"
    )"; then
      printf '%s\n' "${output}"
      return 0
    fi
    log "Rule registry loader failed (${RULE_REGISTRY_LOADER}); falling back to all SQL rules (fail-open)."
  else
    log "Rule registry loader not found (${RULE_REGISTRY_LOADER}); falling back to all SQL rules (fail-open)."
  fi

  for query_file in "${RULE_SQL_DIR}"/*.sql; do
    [ -f "${query_file}" ] || continue
    printf '%s\n' "${query_file}"
  done
}

run_rule() {
  rule_file="$1"
  query_file="$2"

  rule_id="$(yaml_value "${rule_file}" "id")"
  rule_name="$(yaml_value "${rule_file}" "name")"
  severity="$(yaml_value "${rule_file}" "severity")"
  threshold_op="$(yaml_value "${rule_file}" "threshold_op")"
  threshold_value="$(yaml_value "${rule_file}" "threshold_value")"
  window_minutes="$(yaml_value "${rule_file}" "window_minutes")"
  cooldown_seconds="$(yaml_value "${rule_file}" "cooldown_seconds")"
  alert_type="$(yaml_value "${rule_file}" "alert_type")"
  threshold_attempts="$(yaml_value "${rule_file}" "threshold_attempts")"
  threshold_distinct_users="$(yaml_value "${rule_file}" "threshold_distinct_users")"
  threshold_distinct_ips="$(yaml_value "${rule_file}" "threshold_distinct_ips")"
  threshold_failures="$(yaml_value "${rule_file}" "threshold_failures")"
  suppression_computers_csv="$(yaml_value "${rule_file}" "suppression_computers_csv")"
  suppression_users_csv="$(yaml_value "${rule_file}" "suppression_users_csv")"
  suppression_computer_expr="$(yaml_value "${rule_file}" "suppression_computer_expr")"
  suppression_user_expr="$(yaml_value "${rule_file}" "suppression_user_expr")"

  [ -n "${rule_id}" ] || { log "Skipping ${rule_file}: missing id"; return 0; }
  [ -n "${rule_name}" ] || { log "Skipping ${rule_file}: missing name"; return 0; }
  [ -n "${severity}" ] || severity="medium"
  [ -n "${threshold_op}" ] || threshold_op="gte"
  [ -n "${threshold_value}" ] || threshold_value="1"
  [ -n "${window_minutes}" ] || window_minutes="5"
  [ -n "${cooldown_seconds}" ] || cooldown_seconds="0"
  [ -n "${alert_type}" ] || alert_type="${rule_id}"
  [ -n "${threshold_attempts}" ] || threshold_attempts="${threshold_value}"
  [ -n "${threshold_distinct_users}" ] || threshold_distinct_users="${threshold_value}"
  [ -n "${threshold_distinct_ips}" ] || threshold_distinct_ips="${threshold_value}"
  [ -n "${threshold_failures}" ] || threshold_failures="${threshold_value}"
  [ -n "${suppression_computer_expr}" ] || suppression_computer_expr="lowerUTF8(ifNull(fields['computer'], ifNull(fields['hostname'], '')))"
  [ -n "${suppression_user_expr}" ] || suppression_user_expr="lowerUTF8(ifNull(fields['user'], ifNull(fields['username'], ifNull(fields['subject_user_name'], ifNull(fields['target_user_name'], '')))))"

  if [ ! -f "${query_file}" ]; then
    log "Skipping ${rule_id}: missing query file ${query_file}"
    return 0
  fi

  query_block="$(cat "${query_file}")"
  if [ -z "${query_block}" ]; then
    log "Skipping ${rule_id}: empty query file ${query_file}"
    return 0
  fi

  if ! is_integer "${threshold_value}"; then
    log "Skipping ${rule_id}: threshold_value must be integer"
    return 0
  fi

  if ! is_integer "${window_minutes}"; then
    log "Skipping ${rule_id}: window_minutes must be integer"
    return 0
  fi

  if ! is_integer "${cooldown_seconds}"; then
    log "Skipping ${rule_id}: cooldown_seconds must be integer"
    return 0
  fi

  if ! is_integer "${threshold_attempts}" || ! is_integer "${threshold_distinct_users}" || ! is_integer "${threshold_distinct_ips}" || ! is_integer "${threshold_failures}"; then
    log "Skipping ${rule_id}: threshold_attempts / threshold_distinct_users / threshold_distinct_ips / threshold_failures must be integer"
    return 0
  fi

  exec_query="$(normalize_query_for_exec "${query_block}")"
  suppression_condition="$(build_suppression_condition "${suppression_computers_csv}" "${suppression_users_csv}" "${suppression_computer_expr}" "${suppression_user_expr}")"

  if ( [ -n "${suppression_computers_csv}" ] || [ -n "${suppression_users_csv}" ] ) && ! printf '%s' "${exec_query}" | grep -q "{{SUPPRESSION_CONDITION}}"; then
    log "Rule ${rule_id} defines suppression_* values but query has no {{SUPPRESSION_CONDITION}} placeholder; suppressions will not apply."
  fi

  exec_query="$(apply_suppression_condition "${exec_query}" "${suppression_condition}")"
  exec_query="$(apply_rule_placeholders "${exec_query}" "${window_minutes}" "${threshold_attempts}" "${threshold_distinct_users}" "${threshold_distinct_ips}" "${threshold_failures}")"
  result_line="$(query_clickhouse "${exec_query} FORMAT TabSeparated" | head -n1 | tr -d '\r')"
  if [ -z "${result_line}" ]; then
    return 0
  fi
  hits_raw="$(tsv_column "${result_line}" "1")"
  principal_raw="$(tsv_column "${result_line}" "2")"
  source_ip_raw="$(tsv_column "${result_line}" "3")"
  endpoint_id_raw="$(tsv_column "${result_line}" "4")"
  window_start_raw="$(tsv_column "${result_line}" "5")"
  window_end_raw="$(tsv_column "${result_line}" "6")"
  distinct_user_count_raw="$(tsv_column "${result_line}" "7")"
  distinct_ip_count_raw="$(tsv_column "${result_line}" "8")"
  source_kind_raw="$(tsv_column "${result_line}" "9")"
  reason_raw="$(tsv_column "${result_line}" "10")"
  evidence_summary_raw="$(tsv_column "${result_line}" "11")"
  details_raw="$(tsv_column "${result_line}" "12")"
  window_bucket_raw="$(tsv_column "${result_line}" "13")"

  if ! is_integer "${hits_raw}"; then
    log "Rule ${rule_id} returned non-integer result: ${hits_raw}"
    return 0
  fi

  if [ -z "${distinct_user_count_raw}" ]; then
    distinct_user_count_raw="0"
  fi
  if [ -z "${distinct_ip_count_raw}" ]; then
    distinct_ip_count_raw="0"
  fi
  if ! is_integer "${distinct_user_count_raw}" || ! is_integer "${distinct_ip_count_raw}"; then
    log "Rule ${rule_id} returned non-integer distinct counts: users=${distinct_user_count_raw} ips=${distinct_ip_count_raw}"
    return 0
  fi

  if evaluate_threshold "${hits_raw}" "${threshold_op}" "${threshold_value}"; then
    query_compact="$(printf '%s' "${exec_query}" | tr '\n' ' ' | sed -E 's/[[:space:]]+/ /g')"
    escaped_name="$(escape_sql_string "${rule_name}")"
    escaped_alert_type="$(escape_sql_string "${alert_type}")"
    escaped_query="$(escape_sql_string "${query_compact}")"
    escaped_severity="$(escape_sql_string "${severity}")"
    escaped_op="$(escape_sql_string "${threshold_op}")"
    [ -n "${window_start_raw}" ] || window_start_raw="$(default_context_timestamp)"
    [ -n "${window_end_raw}" ] || window_end_raw="$(default_context_timestamp)"
    [ -n "${window_bucket_raw}" ] || window_bucket_raw="${window_end_raw}"
    [ -n "${reason_raw}" ] || reason_raw="Triggered by Hayabusa detection service"
    [ -n "${evidence_summary_raw}" ] || evidence_summary_raw="No additional evidence summary provided"
    [ -n "${details_raw}" ] || details_raw="Triggered by Hayabusa detection service"

    escaped_principal="$(escape_sql_string "${principal_raw}")"
    escaped_source_ip="$(escape_sql_string "${source_ip_raw}")"
    escaped_endpoint_id="$(escape_sql_string "${endpoint_id_raw}")"
    escaped_window_start="$(escape_sql_string "${window_start_raw}")"
    escaped_window_end="$(escape_sql_string "${window_end_raw}")"
    escaped_window_bucket="$(escape_sql_string "${window_bucket_raw}")"
    escaped_source_kind="$(escape_sql_string "${source_kind_raw}")"
    escaped_reason="$(escape_sql_string "${reason_raw}")"
    escaped_evidence_summary="$(escape_sql_string "${evidence_summary_raw}")"
    escaped_details="$(escape_sql_string "${details_raw}")"
    alert_fingerprint_raw="$(build_alert_fingerprint "${alert_type}" "${principal_raw}" "${source_ip_raw}" "${endpoint_id_raw}" "${source_kind_raw}" "${window_bucket_raw}")"
    escaped_alert_fingerprint="$(escape_sql_string "${alert_fingerprint_raw}")"

    if alert_already_recorded "${alert_fingerprint_raw}"; then
      log "Skipped already-recorded alert_type=${alert_type} fingerprint=${alert_fingerprint_raw}"
      return 0
    fi

    if alert_recently_emitted "${alert_fingerprint_raw}" "${cooldown_seconds}"; then
      log "Suppressed alert_type=${alert_type} fingerprint=${alert_fingerprint_raw} due to cooldown_seconds=${cooldown_seconds}"
      return 0
    fi

    query_clickhouse "
INSERT INTO security.alert_candidates
  (
    rule_id,
    rule_name,
    alert_type,
    alert_fingerprint,
    severity,
    hits,
    attempt_count,
    principal,
    entity_user,
    source_ip,
    entity_src_ip,
    endpoint_id,
    entity_host,
    window_start,
    first_seen_ts,
    window_end,
    last_seen_ts,
    window_bucket,
    distinct_user_count,
    distinct_ip_count,
    source_kind,
    reason,
    evidence_summary,
    workflow_state,
    threshold_op,
    threshold_value,
    query,
    details
  )
VALUES
  (
    '${rule_id}',
    '${escaped_name}',
    '${escaped_alert_type}',
    '${escaped_alert_fingerprint}',
    '${escaped_severity}',
    ${hits_raw},
    ${hits_raw},
    '${escaped_principal}',
    '${escaped_principal}',
    '${escaped_source_ip}',
    '${escaped_source_ip}',
    '${escaped_endpoint_id}',
    '${escaped_endpoint_id}',
    '${escaped_window_start}',
    '${escaped_window_start}',
    '${escaped_window_end}',
    '${escaped_window_end}',
    '${escaped_window_bucket}',
    ${distinct_user_count_raw},
    ${distinct_ip_count_raw},
    '${escaped_source_kind}',
    '${escaped_reason}',
    '${escaped_evidence_summary}',
    'new',
    '${escaped_op}',
    ${threshold_value},
    '${escaped_query}',
    '${escaped_details}'
  );
" >/dev/null
    log "Triggered rule=${rule_id} hits=${hits_raw} op=${threshold_op} threshold=${threshold_value} principal=${principal_raw} source_ip=${source_ip_raw} endpoint_id=${endpoint_id_raw}"
  fi
}

main() {
  ensure_schema
  log "Detection service started. polling=${DETECTION_POLL_SECONDS}s rules=${RULE_DIR} sql_rules=${RULE_SQL_DIR} metadata=${RULE_METADATA_DIR}"

  while :; do
    found=0
    for query_file in $(list_enabled_sql_rules); do
      [ -f "${query_file}" ] || continue
      found=1
      rule_id="$(basename "${query_file}" .sql)"
      rule_file="$(find_rule_file_by_id "${rule_id}" || true)"
      if [ -z "${rule_file}" ]; then
        log "Skipping ${query_file}: no rule config with id=${rule_id} found in ${RULE_DIR}"
        continue
      fi
      run_rule "${rule_file}" "${query_file}" || true
    done
    if [ "${found}" -eq 0 ]; then
      log "No enabled SQL rule files found in ${RULE_SQL_DIR}"
    fi

    date -u +"%Y-%m-%dT%H:%M:%SZ" > "${HEARTBEAT_FILE}"
    sleep "${DETECTION_POLL_SECONDS}"
  done
}

main
