# ADR 0003: Declarative SQL detection rules

- Status: Accepted
- Date: 2026-09-21

## Context

Hayabusa needs detections that remain inspectable, testable, and independent of the service implementation.

## Decision

Detection query semantics remain in SQL and rule metadata/configuration. Runtime code owns scheduling, loading, validation, threshold evaluation, deduplication, persistence, and observability; it must not embed individual detection logic.

## Alternatives considered

- Hard-coded Go/Node detections: easier to type-check, but couples each rule to service releases.
- A custom detection DSL: potentially ergonomic later, but creates a new parser/runtime before the product has proved that need.
- External Sigma-only execution: useful future interoperability, but not required for the narrow MVP.

## Consequences

Positive:
- rules are reviewable without reading application code
- rule fixtures can be tested independently
- runtime can evolve without rewriting detection semantics

Negative:
- SQL contracts must be versioned and validated
- rule metadata and SQL can drift unless CI checks their pairing
