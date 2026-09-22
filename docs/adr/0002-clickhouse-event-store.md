# ADR 0002: ClickHouse as the event and detection store

- Status: Accepted
- Date: 2026-09-21

## Context

Hayabusa requires fast append-oriented event storage, time-window queries, SQL-driven detections, and practical local deployment.

## Decision

Use ClickHouse as the canonical persisted event store and query engine for the MVP.

## Alternatives considered

- PostgreSQL: simpler for transactional application data, but less attractive for high-volume analytical event scans.
- Elasticsearch/OpenSearch: strong search ecosystems, but significantly heavier operationally and would move Hayabusa toward a conventional SIEM architecture.
- SQLite/DuckDB: excellent local analytical tools, but less suitable for the continuously running multi-service event pipeline.

## Consequences

Positive:
- SQL remains the primary detection language
- efficient time-window aggregation
- one system can back raw events, normalized views, and detection candidates

Negative:
- ClickHouse-specific SQL and operational knowledge become part of the system
- schema migrations and retention must be managed deliberately
- application code must distinguish analytical storage failures from invalid telemetry
