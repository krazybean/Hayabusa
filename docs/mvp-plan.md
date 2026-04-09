# MVP Plan

## Objective

Build a local Docker Compose stack that proves:
- logs can be ingested
- logs can be stored
- SQL detections can run
- Grafana can alert
- a webhook receiver can receive the alert

## Scope

- Keep:
  - ClickHouse
  - NATS JetStream
  - Vector
  - Grafana
  - detection
  - alert-sink
- Do not add:
  - auth
  - API layer
  - custom frontend
  - clustering
  - Windows endpoint management
  - compliance/reporting
  - advanced detection redesign

## Completed

- Docker Compose boots the strict MVP stack
- Vector accepts demo logs and syslog on `1514`
- Vector accepts one Windows Fluent Bit forward lane on `24225`
- Vector publishes normalized events into JetStream
- Vector consumes buffered events into `security.events`
- ClickHouse exposes endpoint visibility through `security.endpoint_activity`
- Detection polls ClickHouse every 30 seconds
- Detection writes to `security.alert_candidates`
- Grafana provisions one ClickHouse datasource
- Grafana provisions one dashboard
- Grafana provisions alert rules for active detections
- `alert-sink` receives Grafana webhook payloads
- `./scripts/smoke-test.sh` proves ingest -> store -> detect

## Remaining small work

- keep README and docs aligned with the reduced scope
- keep the smoke test green on a clean machine
- keep pinned image and plugin versions intentional when retesting the stack

## Success condition

Run:

```bash
docker compose up -d --remove-orphans
./scripts/smoke-test.sh
docker compose logs --tail=80 alert-sink
```

Success means:
- events exist in `security.events`
- detections exist in `security.alert_candidates`
- Grafana sends a webhook
- `alert-sink` logs the alert payload
