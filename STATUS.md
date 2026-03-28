# Hayabusa Status

Last updated: 2026-03-28 (America/Chicago)

## Current Goal

Build toward Wazuh-comparable capability while keeping the local Docker MVP stable.

## Runtime Snapshot

- Stack health: passing (`./scripts/smoke-test.sh`)
- Ingest path: `Vector -> ClickHouse` active
- Syslog ingest: TCP/UDP `1514` active
- Storage TTL: `7 days` on `security.events`
- Storage budget guardrail: `1 GiB` target via `./scripts/storage-budget-guard.sh`
- Grafana alerts: `Hayabusa Ingest Stalled`, `Hayabusa Events Storage Near Budget`, `Hayabusa Security Failed Login Burst`
- Detection engine MVP: active (`detection` service writes `security.alert_candidates`)
- Detection content: `security_failed_login_burst` enabled, `mvp_high_event_rate` retained as fallback
- Alert routing MVP: Grafana contact points + policy + dedupe to local `alert-sink` router webhook, with optional external forward auth token

## Component Progress

- Foundation: complete for MVP
- Collection: partial
- Ingestion/Normalization: partial
- Transport (NATS in active path): not started
- Storage: solid baseline
- Detection engine: MVP complete
- Alert routing/policy: MVP complete (local webhook + optional external forward)
- Investigation workflow: early

## Next Priority Queue

1. Activate NATS JetStream in live data path
2. Host collector strategy (Fluent Bit + Windows events)
3. Detection content expansion (security-focused rules + correlation)
4. Alert delivery hardening (external destinations, retries, auth, secrets)

## Session Rebuild Fast Path

1. `./scripts/smoke-test.sh`
2. `./scripts/storage-budget-guard.sh`
3. `docker compose logs --tail=120 vector`
4. `docker compose logs --tail=120 grafana`
5. Review `docs/component-checklist.md`, `docs/wazuh-parity-map.md`, and `docs/mvp-plan.md`

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
