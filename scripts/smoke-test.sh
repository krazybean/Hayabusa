#!/usr/bin/env bash
set -euo pipefail

TIMEOUT_SECONDS="${SMOKE_TIMEOUT_SECONDS:-180}"
SLEEP_SECONDS=2
NATS_STREAM_NAME="${SMOKE_NATS_STREAM_NAME:-HAYABUSA_EVENTS}"
NATS_CONSUMER_NAME="${SMOKE_NATS_CONSUMER_NAME:-HAYABUSA_INGEST}"
ALERT_POLL_ATTEMPTS="${SMOKE_ALERT_POLL_ATTEMPTS:-40}"
SMOKE_RULE_ID="${SMOKE_RULE_ID:-security_source_multi_user_burst}"

timestamp() {
  date +"%H:%M:%S"
}

wait_for_http() {
  local name="$1"
  local url="$2"
  local pattern="${3:-}"
  local elapsed=0

  printf "[%s] Waiting for %s at %s\n" "$(timestamp)" "${name}" "${url}"

  while (( elapsed < TIMEOUT_SECONDS )); do
    local body
    if body="$(curl -fsS "${url}" 2>/dev/null)"; then
      if [[ -z "${pattern}" ]] || grep -qi "${pattern}" <<<"${body}"; then
        printf "[%s] OK: %s\n" "$(timestamp)" "${name}"
        return 0
      fi
    fi
    sleep "${SLEEP_SECONDS}"
    elapsed=$((elapsed + SLEEP_SECONDS))
  done

  printf "[%s] ERROR: %s did not become ready within %ss\n" "$(timestamp)" "${name}" "${TIMEOUT_SECONDS}" >&2
  return 1
}

run_nats_cli() {
  docker compose run --rm --no-deps nats-init \
    nats --server nats://nats:4222 "$@"
}

wait_for_detection() {
  local elapsed=0
  printf "[%s] Waiting for detection heartbeat\n" "$(timestamp)"

  while (( elapsed < TIMEOUT_SECONDS )); do
    if docker compose exec -T detection sh -c "test -f /tmp/detection-heartbeat" >/dev/null 2>&1; then
      printf "[%s] OK: Detection service\n" "$(timestamp)"
      return 0
    fi
    sleep "${SLEEP_SECONDS}"
    elapsed=$((elapsed + SLEEP_SECONDS))
  done

  printf "[%s] ERROR: Detection service did not become ready within %ss\n" "$(timestamp)" "${TIMEOUT_SECONDS}" >&2
  return 1
}

wait_for_ingest() {
  local elapsed=0
  printf "[%s] Waiting for hayabusa-ingest\n" "$(timestamp)"

  while (( elapsed < TIMEOUT_SECONDS )); do
    if docker compose exec -T hayabusa-ingest sh -c "test -r /proc/1/status" >/dev/null 2>&1; then
      printf "[%s] OK: hayabusa-ingest\n" "$(timestamp)"
      return 0
    fi
    sleep "${SLEEP_SECONDS}"
    elapsed=$((elapsed + SLEEP_SECONDS))
  done

  printf "[%s] ERROR: hayabusa-ingest did not become ready within %ss\n" "$(timestamp)" "${TIMEOUT_SECONDS}" >&2
  return 1
}

query_scalar() {
  local sql="$1"
  curl -fsS "http://localhost:8123/" --data-binary "${sql}" | tr -d '\r\n'
}

count_alert_sink_rule_hits() {
  docker compose logs alert-sink 2>/dev/null \
    | awk -v rule_id="${SMOKE_RULE_ID}" '/payload path=\/alerts\/default/ && index($0, rule_id) > 0 { count += 1 } END { print count + 0 }'
}

send_password_spray() {
  ./scripts/load-synthetic-auth.sh --clear --scenario password-spray >/tmp/hayabusa-smoke-synthetic-auth.log
}

echo "Running Hayabusa MVP smoke test..."

wait_for_http "ClickHouse" "http://localhost:8123/ping" "ok"
wait_for_http "Vector" "http://localhost:8686/health"
wait_for_ingest
wait_for_http "Hayabusa API" "http://localhost:8080/health" "\"ok\":true"
wait_for_http "Hayabusa Web" "http://localhost:3000/"
wait_for_http "Alert Router" "http://localhost:5678/health" "\"ok\":true"
wait_for_http "Grafana" "http://localhost:3001/api/health" "\"database\"[[:space:]]*:[[:space:]]*\"ok\""
wait_for_detection

stream_info="$(run_nats_cli stream info "${NATS_STREAM_NAME}")"
if grep -q "Stream ${NATS_STREAM_NAME}" <<<"${stream_info}"; then
  printf "[%s] OK: JetStream stream present (%s)\n" "$(timestamp)" "${NATS_STREAM_NAME}"
else
  printf "[%s] ERROR: JetStream stream missing (%s)\n" "$(timestamp)" "${NATS_STREAM_NAME}" >&2
  exit 1
fi

consumer_info="$(run_nats_cli consumer info "${NATS_STREAM_NAME}" "${NATS_CONSUMER_NAME}")"
if grep -q "Name: ${NATS_CONSUMER_NAME}" <<<"${consumer_info}"; then
  printf "[%s] OK: JetStream consumer present (%s)\n" "$(timestamp)" "${NATS_CONSUMER_NAME}"
else
  printf "[%s] ERROR: JetStream consumer missing (%s)\n" "$(timestamp)" "${NATS_CONSUMER_NAME}" >&2
  exit 1
fi

events_before="$(query_scalar "SELECT count() FROM security.events FORMAT TabSeparated")"
alert_hits_before="$(count_alert_sink_rule_hits)"
send_password_spray
sleep 5
events_after="$(query_scalar "SELECT count() FROM security.events FORMAT TabSeparated")"

if [[ "${events_before}" =~ ^[0-9]+$ ]] && [[ "${events_after}" =~ ^[0-9]+$ ]] && (( events_after > events_before )); then
  printf "[%s] OK: events ingested into ClickHouse (%s -> %s)\n" "$(timestamp)" "${events_before}" "${events_after}"
else
  printf "[%s] ERROR: events did not increase in ClickHouse (%s -> %s)\n" "$(timestamp)" "${events_before}" "${events_after}" >&2
  exit 1
fi

candidate_count="0"
attempt=0
until (( attempt >= 20 )); do
  candidate_count="$(query_scalar "SELECT count() FROM security.alert_candidates WHERE rule_id = '${SMOKE_RULE_ID}' AND ts > now() - INTERVAL 10 MINUTE FORMAT TabSeparated")"
  if [[ "${candidate_count}" =~ ^[0-9]+$ ]] && (( candidate_count > 0 )); then
    break
  fi
  sleep 3
  attempt=$((attempt + 1))
done

if [[ "${candidate_count}" =~ ^[0-9]+$ ]] && (( candidate_count > 0 )); then
  printf "[%s] OK: detection wrote alert candidate rows (%s)\n" "$(timestamp)" "${candidate_count}"
else
  printf "[%s] ERROR: detection did not write alert candidates\n" "$(timestamp)" >&2
  exit 1
fi

alert_hits_after="${alert_hits_before}"
attempt=0
until (( attempt >= ALERT_POLL_ATTEMPTS )); do
  alert_hits_after="$(count_alert_sink_rule_hits)"
  if [[ "${alert_hits_after}" =~ ^[0-9]+$ ]] && [[ "${alert_hits_before}" =~ ^[0-9]+$ ]] && (( alert_hits_after > alert_hits_before )); then
    break
  fi
  sleep 3
  attempt=$((attempt + 1))
done

if [[ "${alert_hits_after}" =~ ^[0-9]+$ ]] && [[ "${alert_hits_before}" =~ ^[0-9]+$ ]] && (( alert_hits_after > alert_hits_before )); then
  printf "[%s] OK: Grafana sent webhook alert to alert-sink (%s -> %s)\n" "$(timestamp)" "${alert_hits_before}" "${alert_hits_after}"
else
  printf "[%s] ERROR: Grafana webhook alert was not observed in alert-sink logs (%s -> %s)\n" "$(timestamp)" "${alert_hits_before}" "${alert_hits_after}" >&2
  exit 1
fi

echo "Smoke test passed."
