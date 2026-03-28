# Architecture

## Whole-system flow

```text
collect -> normalize -> buffer -> store -> detect -> alert -> investigate
```

## Segments

### Foundation
Core infrastructure:
- ClickHouse
- ClickHouse Keeper
- NATS JetStream
- Grafana
- Prometheus

Open-source options:
- Event store: ClickHouse, TimescaleDB, Apache Druid
- Coordination: ClickHouse Keeper, ZooKeeper
- Message bus: NATS JetStream, Kafka, RabbitMQ
- Dashboards: Grafana
- Metrics: Prometheus, VictoriaMetrics

Recommended:
- ClickHouse
- ClickHouse Keeper
- NATS JetStream
- Grafana
- Prometheus

### Collection
Purpose:
- collect logs from Linux, Windows, apps, and network devices
- forward with minimal buffering and tagging

Options:
- Fluent Bit
- Vector
- OpenTelemetry Collector

Recommended:
- Fluent Bit later for endpoints
- Vector for local MVP

### Ingestion / Normalization
Purpose:
- parse raw input
- normalize into canonical events
- route downstream

Options:
- Vector
- Logstash
- Fluent Bit

Recommended:
- Vector

### Transport / Buffering
Purpose:
- durable buffering
- replay
- decoupling

Options:
- NATS JetStream
- Kafka
- RabbitMQ

Recommended:
- NATS JetStream

### Storage / Query
Purpose:
- durable event storage
- fast analytical queries
- retention and lifecycle

Options:
- ClickHouse
- TimescaleDB
- Apache Druid

Recommended:
- ClickHouse + ClickHouse Keeper

### Detection
Purpose:
- threshold detections
- correlation
- SQL-backed rules
- alert candidates

Options:
- custom Go service
- custom Python service
- custom Rust service

Recommended:
- custom service (MVP in repo)
- YAML rules
- SQL-first detections

### Enrichment
Purpose:
- GeoIP
- threat intel
- asset context
- identity context

Recommended:
- simple local enrichment later

### Alerting
Purpose:
- dedupe
- throttling
- routing
- notification fan-out

Options:
- custom alert router
- Alertmanager
- Grafana Alerting

Recommended:
- custom service later

### Presentation
Purpose:
- dashboards
- search/hunt views
- triage later

Options:
- Grafana
- React + Go API later
- React + FastAPI later

Recommended:
- Grafana first

### Operations / Observability
Purpose:
- monitor the platform itself
- queue depth
- dropped events
- rule latency
- storage health

Recommended:
- Prometheus + Grafana

### Configuration / Control Plane
Purpose:
- global defaults
- environment overrides
- per-service config
- rule definitions

Format:
- YAML for human-authored config
- env vars or secrets for sensitive values
