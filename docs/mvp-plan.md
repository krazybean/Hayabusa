# MVP Plan

## Objective

Build a local, runnable starter stack that proves:
- services can start together
- config layout is stable
- observability tools are reachable
- ClickHouse exists as the future event store
- Vector exists as the future ingestion layer
- NATS exists as the future transport layer

## Phase 1: Local foundation (completed)

Deliver:
- Docker Compose stack
- ClickHouse
- ClickHouse Keeper
- NATS JetStream
- Grafana
- Prometheus
- Vector

## Phase 2: Basic ingestion path (completed)

Deliver:
- Vector reads a local demo source
- Vector normalizes events
- Vector writes to console for debug visibility

## Phase 3: First storage integration (completed)

Deliver:
- create a ClickHouse database (`security`)
- add an events table (`security.events`)
- route a basic normalized stream into ClickHouse

## Phase 4: Metrics and dashboards (completed)

Deliver:
- Prometheus scrape config
- Grafana datasource provisioning
- first Grafana dashboard for `security.events` visibility

## Phase 5: Detection placeholder (completed)

Deliver:
- repo structure for future detection engine
- rules directory in YAML

## Phase 6: Detection engine MVP (completed)

Deliver:
- detection service container in Docker Compose
- YAML rule execution against ClickHouse
- triggered candidates persisted to `security.alert_candidates`

## Phase 7: Active transport/buffer path (completed)

Deliver:
- NATS JetStream stream/consumer bootstrap in compose startup
- Vector route updated to `normalize -> JetStream -> ClickHouse`
- Smoke test checks for JetStream stream/consumer/subject wiring

## Phase 8: Host collector baseline (completed)

Deliver:
- Fluent Bit service added to Docker Compose for host-log collection
- Fluent Bit forward protocol integrated into Vector ingest path
- Smoke test validates Fluent Bit -> Vector -> JetStream -> ClickHouse flow

## Phase 9: Windows collection strategy (completed)

Deliver:
- Windows Fluent Bit `winevtlog` config template
- Baseline field mapping expectations into Vector normalization
- Windows collection runbook for endpoint setup and validation

## Next focus

- Define canonical normalized schema versioning strategy
- Harden alert delivery (external destinations, auth, retries, secret management)
- Add first saved query pack for investigation workflows
- Windows endpoint rollout validation (real host test + hardening)
