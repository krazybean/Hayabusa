# Architecture

## Goal

```text
ingest -> store -> detect -> alert
```

Hayabusa is intentionally a small local Docker Compose proof-of-function stack.

```mermaid
flowchart LR
  Sources[Vector demo logs + syslog 1514] --> Vector[Vector]
  Vector --> NATS[(NATS JetStream)]
  NATS --> ClickHouse[(ClickHouse security.events)]
  ClickHouse --> Detection[Detection shell service]
  Detection --> Candidates[(security.alert_candidates)]
  ClickHouse --> Grafana[Grafana dashboard + alert rule]
  Candidates --> Grafana
  Grafana --> Router[alert-sink webhook]
  Router -. optional forward .-> External[External webhook]
```

## Runtime Pieces

- `vector`: accepts demo logs and syslog, normalizes them, publishes to JetStream, then consumes from JetStream into ClickHouse
- `nats` + `nats-init`: provides the `HAYABUSA_EVENTS` stream and `VECTOR_CLICKHOUSE_WRITER` consumer
- `clickhouse`: stores normalized logs in `security.events` and detection output in `security.alert_candidates`
- `detection`: runs one YAML-defined SQL rule every 30 seconds and inserts matches into `security.alert_candidates`
- `grafana`: provides one ClickHouse-backed dashboard and one alert rule
- `alert-sink`: receives Grafana webhook payloads and logs them; optional forwarding stays available through env vars

## Non-Goals

- no auth
- no API layer
- no custom frontend
- no clustering or HA
- no endpoint management
- no Windows collection lane
- no compliance or investigation workflow
