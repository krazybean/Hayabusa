# Hayabusa Status

Last updated: 2026-03-29 (America/Chicago)

## Current Goal

Build toward Wazuh-comparable capability while keeping the local Docker MVP stable.

## Runtime Snapshot

- Stack health: passing (`./scripts/smoke-test.sh`)
- Ingest path: `Vector -> NATS JetStream -> ClickHouse` active
- JetStream stream: `HAYABUSA_EVENTS` (`hayabusa.events.>`, max bytes `256 MiB`, max age `24h`)
- JetStream durable consumer: `VECTOR_CLICKHOUSE_WRITER`
- Syslog ingest: TCP/UDP `1514` active
- Host collector path: `Fluent Bit (tail) -> Vector forward (24224)` active
- Windows event collector path: strategy + template + validation script (`winevtlog -> forward -> Vector:24225`)
- Windows lane local simulator: active (`./scripts/generate-windows-events.sh` -> `vector-windows-endpoint`)
- Windows mTLS hardening toolkit: ready (`./scripts/generate-windows-forward-certs.sh` + mTLS templates)
- Windows lane mTLS: enabled in active stack (`vector` source TLS + fluent-bit client cert output)
- Windows endpoint enrollment: bundle script + endpoint-specific client certs (`./scripts/enroll-windows-endpoint.sh`)
- Storage TTL: `7 days` on `security.events`
- Storage budget guardrail: `1 GiB` target via `./scripts/storage-budget-guard.sh`
- Grafana alerts: `Hayabusa Ingest Stalled`, `Hayabusa Events Storage Near Budget`, `Hayabusa Security Failed Login Burst`
- Detection engine MVP: active (`detection` service writes `security.alert_candidates`)
- Detection content: baseline + Windows EventID pack enabled (`4625`, `4740`, `4697/7045`, `4728/4732/4756`)
- Detection correlation: Windows multi-signal rule pack active (`4625->4740`, `4625->4697/7045`, `4625->4728/4732/4756`, `4740->4697/7045`)
- Detection noise control: per-rule `cooldown_seconds` suppression active
- Alert routing MVP: Grafana contact points + policy + dedupe to local `alert-sink` router webhook, with optional external forward auth token
- Investigation query pack: starter SQL hunts added (`docs/investigation-query-pack.md`)
- Investigation dashboard: provisioned (`Hayabusa Investigations`)

## Component Progress

- Foundation: complete for MVP
- Collection: strong-mvp (Windows lane validated locally; mTLS active; enrollment bundle flow added)
- Ingestion/Normalization: partial
- Transport (NATS in active path): MVP complete
- Storage: solid baseline
- Detection engine: MVP complete
- Alert routing/policy: MVP complete (local webhook + optional external forward)
- Investigation workflow: early

## Next Priority Queue

1. First real Windows host deployment using endpoint enrollment bundle
2. Alert delivery hardening (external destinations, retries, auth, secrets)
3. Investigation workflow playbooks tied to dashboard pivots
4. Detection tuning (false-positive controls, host/user-level suppressions)

## Session Rebuild Fast Path

1. `./scripts/smoke-test.sh`
2. `./scripts/storage-budget-guard.sh`
3. `docker compose logs --tail=120 vector`
4. `docker compose logs --tail=120 fluent-bit`
5. `docker compose logs --tail=120 grafana`
6. `./scripts/windows-endpoint-check.sh` (after onboarding a real Windows host)
7. Review `docs/component-checklist.md`, `docs/wazuh-parity-map.md`, `docs/mvp-plan.md`, and `docs/windows-event-collection.md`

## Linear Tracking

- Target team (requested): `HAY` (`https://linear.app/hayabusa/team/HAY/active`)
- Current MCP auth context in this session: `beansocial` workspace only
- Canceled placeholder issues created in wrong team: `BEA-180`, `BEA-181`, `BEA-182`
- Action needed: connect/switch Linear MCP auth to Hayabusa workspace, then recreate issues in `HAY`

## Feature Wrap-Up Rule

At the end of every feature:

1. Move Linear issue state (`In Progress -> In Review -> Done`)
2. Run smoke test + targeted verification
3. Update `STATUS.md`
4. Update `docs/component-checklist.md`
5. Update any user-facing runbook/docs (`README.md`, relevant docs)
