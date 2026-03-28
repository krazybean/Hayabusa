#!/usr/bin/env sh
set -eu

NATS_URL="${NATS_URL:-nats://nats:4222}"
STREAM_NAME="${NATS_STREAM_NAME:-HAYABUSA_EVENTS}"
STREAM_SUBJECTS="${NATS_STREAM_SUBJECTS:-hayabusa.events.>}"
CONSUMER_NAME="${NATS_CONSUMER_NAME:-VECTOR_CLICKHOUSE_WRITER}"
STREAM_MAX_BYTES="${NATS_STREAM_MAX_BYTES:-268435456}"
STREAM_MAX_AGE="${NATS_STREAM_MAX_AGE:-24h}"
MAX_ATTEMPTS="${NATS_BOOTSTRAP_MAX_ATTEMPTS:-90}"

echo "[nats-init] Waiting for NATS at ${NATS_URL}"
attempt=0
until nats --server "${NATS_URL}" account info >/dev/null 2>&1; do
  attempt=$((attempt + 1))
  if [ "${attempt}" -ge "${MAX_ATTEMPTS}" ]; then
    echo "[nats-init] ERROR: NATS did not become ready in time"
    exit 1
  fi
  sleep 1
done

if nats --server "${NATS_URL}" stream info "${STREAM_NAME}" >/dev/null 2>&1; then
  echo "[nats-init] Stream exists: ${STREAM_NAME}"
else
  echo "[nats-init] Creating stream: ${STREAM_NAME}"
  nats --server "${NATS_URL}" stream add "${STREAM_NAME}" \
    --subjects "${STREAM_SUBJECTS}" \
    --storage file \
    --retention limits \
    --discard old \
    --max-bytes "${STREAM_MAX_BYTES}" \
    --max-age "${STREAM_MAX_AGE}" \
    --defaults >/dev/null
fi

if nats --server "${NATS_URL}" consumer info "${STREAM_NAME}" "${CONSUMER_NAME}" >/dev/null 2>&1; then
  echo "[nats-init] Consumer exists: ${CONSUMER_NAME}"
else
  echo "[nats-init] Creating consumer: ${CONSUMER_NAME}"
  nats --server "${NATS_URL}" consumer add "${STREAM_NAME}" "${CONSUMER_NAME}" \
    --pull \
    --ack explicit \
    --deliver all \
    --replay instant \
    --defaults >/dev/null
fi

echo "[nats-init] JetStream bootstrap complete"
