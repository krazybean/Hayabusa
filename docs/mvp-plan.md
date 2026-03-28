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

## Next focus

- Define canonical normalized schema versioning strategy
- Introduce NATS into the active data path (`normalize -> buffer -> store`)
- Harden alert delivery (external destinations, auth, retries, secret management)
- Add first saved query pack for investigation workflows
- Expand smoke tests with NATS JetStream stream/consumer validation once subjects are defined
