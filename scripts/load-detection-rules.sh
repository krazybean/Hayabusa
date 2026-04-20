#!/bin/sh
set -eu

RULE_SQL_DIR="${RULE_SQL_DIR:-/etc/hayabusa/detections/rules}"
RULE_METADATA_DIR="${RULE_METADATA_DIR:-/etc/hayabusa/detections/metadata}"

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

normalize_bool() {
  printf '%s' "$1" | tr '[:upper:]' '[:lower:]' | tr -d '[:space:]'
}

is_disabled() {
  value="$(normalize_bool "$1")"
  [ "${value}" = "false" ] || [ "${value}" = "0" ] || [ "${value}" = "no" ]
}

disabled_ids_file="$(mktemp)"
trap 'rm -f "${disabled_ids_file}"' EXIT

for metadata_file in "${RULE_METADATA_DIR}"/*.yaml; do
  [ -f "${metadata_file}" ] || continue
  rule_id="$(yaml_value "${metadata_file}" "id")"
  [ -n "${rule_id}" ] || continue
  query_file="${RULE_SQL_DIR}/${rule_id}.sql"
  [ -f "${query_file}" ] || continue
  enabled_value="$(yaml_value "${metadata_file}" "enabled")"
  if [ -n "${enabled_value}" ] && is_disabled "${enabled_value}"; then
    printf '%s\n' "${rule_id}" >> "${disabled_ids_file}"
  fi
done

for query_file in "${RULE_SQL_DIR}"/*.sql; do
  [ -f "${query_file}" ] || continue
  rule_id="$(basename "${query_file}" .sql)"
  if grep -Fxq "${rule_id}" "${disabled_ids_file}"; then
    continue
  fi
  printf '%s\n' "${query_file}"
done
