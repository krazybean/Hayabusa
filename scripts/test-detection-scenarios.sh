#!/usr/bin/env bash
set -euo pipefail

POLL_ATTEMPTS="${DETECTION_TEST_POLL_ATTEMPTS:-20}"
POLL_SECONDS="${DETECTION_TEST_POLL_SECONDS:-2}"

query_scalar() {
  docker compose exec -T clickhouse clickhouse-client --query "$1" | tr -d '\r\n'
}

reset_state() {
  docker compose exec -T clickhouse clickhouse-client --query "TRUNCATE TABLE security.alert_candidates"
  docker compose exec -T clickhouse clickhouse-client --query "TRUNCATE TABLE security.events"
  find data/synthetic-auth -maxdepth 1 -type f -name '*.jsonl' -delete
}

wait_for_auth_events() {
  local expected="$1"
  local attempt=0
  local count=0
  until (( attempt >= POLL_ATTEMPTS )); do
    count="$(query_scalar "SELECT count() FROM security.auth_events WHERE ingest_source = 'synthetic-auth'")"
    if [[ "${count}" =~ ^[0-9]+$ ]] && (( count >= expected )); then
      return 0
    fi
    sleep "${POLL_SECONDS}"
    attempt=$((attempt + 1))
  done
  echo "ERROR: expected at least ${expected} synthetic auth events, got ${count}" >&2
  return 1
}

wait_for_rule() {
  local rule_id="$1"
  local attempt=0
  local count=0
  until (( attempt >= POLL_ATTEMPTS )); do
    count="$(query_scalar "SELECT count() FROM security.alert_candidates WHERE rule_id = '${rule_id}'")"
    if [[ "${count}" =~ ^[0-9]+$ ]] && (( count > 0 )); then
      echo "PASS: ${rule_id} fired"
      return 0
    fi
    sleep "${POLL_SECONDS}"
    attempt=$((attempt + 1))
  done
  echo "ERROR: expected rule ${rule_id} to fire" >&2
  docker compose logs --tail=100 detection >&2 || true
  return 1
}

run_positive() {
  local scenario="$1"
  local expected_events="$2"
  local rule_id="$3"
  echo "Scenario: ${scenario} -> ${rule_id}"
  reset_state
  ./scripts/load-synthetic-auth.sh --scenario "${scenario}" --clear >/dev/null
  wait_for_auth_events "${expected_events}"
  wait_for_rule "${rule_id}"
}

echo "Running detection scenario tests..."

reset_state
./scripts/load-synthetic-auth.sh --scenario benign-success --clear >/dev/null
wait_for_auth_events 4
sleep 7
benign_alerts="$(query_scalar "SELECT count() FROM security.alert_candidates")"
if [[ "${benign_alerts}" != "0" ]]; then
  echo "ERROR: benign-success produced ${benign_alerts} alert(s)" >&2
  docker compose exec -T clickhouse clickhouse-client --query \
    "SELECT rule_id, alert_type, hits, reason FROM security.alert_candidates FORMAT PrettyCompact" >&2 || true
  exit 1
fi
echo "PASS: benign-success stayed quiet"

run_positive password-spray 4 security_source_multi_user_burst
run_positive distributed-attack 4 security_user_multi_source_burst
run_positive fail-then-success 4 security_failed_then_success

echo "Detection scenario tests passed."
