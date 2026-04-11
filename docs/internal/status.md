# Internal Only — Not User-Facing

# Hayabusa Status

Last updated: 2026-04-09 (America/Chicago)

## Current Goal

Keep the strict local MVP working for one proof path:

```text
ingest -> store -> detect -> alert
```

## Runtime Snapshot

- Stack health: passing (`./scripts/smoke-test.sh`)
- Dev branch validation: GitHub Actions runs `docker compose config` and `./scripts/smoke-test.sh` on push to `dev`
- Runtime pinning: core images pinned to the tested versions/digests in `docker-compose.yml`
- Grafana plugin pinning: `grafana-clickhouse-datasource@4.14.0`
- Ingest path: `Vector -> NATS JetStream -> ClickHouse` active
- JetStream stream: `HAYABUSA_EVENTS` (`events.auth`, max bytes `256 MiB`, max age `24h`)
- JetStream durable consumer: `VECTOR_CLICKHOUSE_WRITER`
- Syslog ingest: TCP/UDP `1514` active
- Canonical schema contract: `hayabusa.event.v1` active (`schema_version` anchor + contract doc)
- Auth query seam: `security.auth_events` view present for readable auth detections and investigations
- Grafana dashboard: `Hayabusa Overview`
- Grafana alerts: `Hayabusa Security Failed Login Burst`, `Hayabusa Windows Failed Logon Burst`, plus v1.1 auth detections for password spray, fail-then-success, and distributed attack
- Detection engine MVP: active (`detection` service writes `security.alert_candidates`)
- Active detection rules: `security_failed_login_burst`, `security_source_multi_user_burst` (`password_spray`), `security_user_multi_source_burst` (`distributed_attack`), `security_failed_then_success` (`fail_then_success`), `windows_failed_logon_burst`
- Alert candidate dedupe: fingerprint-based suppression for repeated runs of the same alert window bucket
- Alert routing MVP: Grafana posts firing alerts to local `alert-sink`
- External forwarding: optional via `HAYABUSA_EXTERNAL_WEBHOOK_URL`
- Linux collector path: SSH auth log -> Vector on host -> NATS -> `security.events`
- Windows first-host path: Vector on host -> NATS -> `security.events`
- Endpoint visibility: `security.endpoint_activity` view + `./scripts/endpoint-activity-report.sh`
- Windows first-host validation runbook: `WINDOWS_REAL_HOST_RUNBOOK.md`
- Lightweight demo surface: `docs/index.html` + `docs/styles.css`

## Keep

- `docker-compose.yml`
- Vector config
- ClickHouse schema
- one detection rule
- one dashboard
- one Grafana alert
- one webhook receiver
- one smoke test

## Deferred Until Post-MVP

- Prometheus
- ClickHouse Keeper
- Fluent Bit runtime path
- Windows fleet management beyond one real host
- investigation workflows
- compliance and parity work
- extra rule packs and extra alert routes
- any requirement for external alert forwarding

## Notes

- On an existing dev machine, `docker compose up` may warn about orphan containers from the older wider stack. Use `docker compose up -d --remove-orphans` for a clean local reset.
- On first boot, Grafana may take longer to become ready because it downloads the pinned ClickHouse datasource plugin.
- On a clean machine, first boot currently assumes outbound network access for that Grafana plugin download.
- The smoke test proves ingest -> store -> detect -> alert.
