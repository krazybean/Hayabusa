# ADR 0001: NATS JetStream as the event transport

- Status: Accepted
- Date: 2026-09-21

## Context

Hayabusa needs a small, local-first transport between collectors and ingest. The transport must tolerate temporary ingest downtime, provide durable delivery semantics, and remain easy to run in Docker Compose and on homelab hardware.

## Decision

Use NATS JetStream for the MVP event transport.

## Alternatives considered

- Kafka: mature and capable, but operationally heavier than the current local-first scope requires.
- RabbitMQ: viable durable broker, but less aligned with the lightweight subject/stream model used by the current pipeline.
- Redis Streams: simple to operate, but would couple another general-purpose datastore into a path where a dedicated message system is clearer.
- Direct HTTP ingestion: smallest component count, but removes buffering and makes collector availability depend directly on ingest availability.

## Consequences

Positive:
- small operational footprint
- durable stream/consumer semantics
- natural subject-based event routing
- collectors and ingest remain decoupled

Negative:
- NATS authentication/TLS must be configured before exposing collector ingress beyond trusted networks
- JetStream state becomes an operational dependency
- transport-specific bootstrap and monitoring are required
