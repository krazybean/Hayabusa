# Hayabusa Status

Last updated: 2026-04-01 (America/Chicago)

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
- Windows real-host cutover guard: endpoint-specific validation + CIDR hardening check (`./scripts/windows-real-host-cutover-check.sh`)
- Windows cutover orchestrator: one-command workflow (`./scripts/windows-cutover-orchestrator.sh`)
- Canonical schema contract: `hayabusa.event.v1` active (`schema_version` anchor + contract doc)
- Endpoint visibility baseline: telemetry-derived inventory view + report script (`security.endpoint_activity`, `./scripts/endpoint-activity-report.sh`)
- Endpoint policy/drift baseline: YAML policy + drift checker (`configs/endpoints/windows-endpoints.yaml`, `./scripts/endpoint-policy-drift-check.sh`)
- Endpoint policy automation: upsert workflow integrated (`./scripts/upsert-endpoint-policy.sh` + enrollment/cutover wiring)
- Storage TTL: `7 days` on `security.events`
- Storage budget guardrail: `1 GiB` target via `./scripts/storage-budget-guard.sh`
- Grafana alerts: ingest stall + storage budget + failed-login burst + Windows correlation rule alerts
- Detection engine MVP: active (`detection` service writes `security.alert_candidates`)
- Detection content: baseline + Windows EventID pack enabled (`4625`, `4740`, `4697/7045`, `4728/4732/4756`)
- Detection correlation: Windows multi-signal rule pack active (`4625->4740`, `4625->4697/7045`, `4625->4728/4732/4756`, `4740->4697/7045`)
- Detection noise control: per-rule `cooldown_seconds` suppression active
- Detection scoped suppressions: host/user suppression controls active (`suppression_*` + `{{SUPPRESSION_CONDITION}}`)
- Detection tuning wave 2 baseline: threshold recalibration + curated simulator suppression list (`win-local-sim`) in Windows-focused rules
- Alert routing MVP: Grafana contact points + policy + dedupe to local `alert-sink` router webhook, with optional external forward auth token
- Alert router hardening: external webhook timeout + retry/backoff controls (`HAYABUSA_ALERT_ROUTER_FORWARD_*`)
- Alert destination fan-out: platform/email + detection/chat + on-call path routing with route-specific external webhook overrides
- Investigation query pack: starter SQL hunts added (`docs/investigation-query-pack.md`)
- Investigation dashboard: provisioned (`Hayabusa Investigations`)
- Investigation playbooks: documented and mapped to dashboard pivots (`docs/investigation-playbooks.md`)

## Component Progress

- Foundation: complete for MVP
- Collection: strong-mvp (Windows lane validated locally; mTLS active; enrollment bundle flow added)
- Ingestion/Normalization: partial
- Transport (NATS in active path): MVP complete
- Storage: solid baseline
- Detection engine: MVP complete
- Alert routing/policy: partial-strong (fan-out paths + retry hardening)
- Investigation workflow: partial
- Endpoint/agent management: partial baseline (inventory + YAML policy + automated drift/promotion workflow)

## Next Priority Queue

1. First real Windows host deployment using endpoint enrollment bundle (`--first-real-host`)
2. Endpoint lifecycle policy (certificate rotation/revocation + decommission workflow)
3. Compliance/reporting starter pack
4. Investigation workflow acceleration (case linkage + analyst workflow automation)

## Session Rebuild Fast Path

1. `./scripts/smoke-test.sh`
2. `./scripts/storage-budget-guard.sh`
3. `docker compose logs --tail=120 vector`
4. `docker compose logs --tail=120 fluent-bit`
5. `docker compose logs --tail=120 grafana`
6. `./scripts/windows-endpoint-check.sh` (after onboarding a real Windows host)
7. `./scripts/apply-clickhouse-migrations.sh`
8. `./scripts/endpoint-activity-report.sh --lane vector-windows-endpoint`
9. `./scripts/endpoint-policy-drift-check.sh --soft-fail`
10. `./scripts/windows-cutover-orchestrator.sh --endpoint-id WIN-ENDPOINT-01 --vector-host <host> --expected-cidr <cidr> --computer WIN-ENDPOINT-01 --dry-run`
11. Review `docs/component-checklist.md`, `docs/wazuh-parity-map.md`, `docs/mvp-plan.md`, and `docs/windows-event-collection.md`

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
