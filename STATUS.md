# STATUS.md

## Current State

Hayabusa is a working MVP demonstrating:

ingest → store → detect → alert

via a local docker-compose stack.

---

## Proven Capabilities

- events flow through Vector → NATS → ingest → ClickHouse
- normalized auth events exist in `security.auth_events`
- detections write to `security.alert_candidates`
- alerts surface via Grafana + alert-sink
- synthetic attack simulation triggers detections

---

## Current Strengths

- fully local-first
- fast demo loop
- observable pipeline
- simple deployment
- clear event schema contract

---

## Active Gaps

- no formal API layer
- detection system lacks metadata/test harness
- orchestration is implicit (scripts + cron style)
- logic spread across configs + services
- no clear extensibility interface yet

---

## Immediate Priorities

1. formalize engineering system (AGENTS.md, ENGINEERING_SYSTEM.md)
2. stabilize detection structure
3. improve observability consistency
4. prepare for API introduction
5. reduce implicit logic spread

---

## Deferred Scope

- multi-tenant support
- auth / RBAC
- clustering / HA
- enterprise workflows
- external alert routing

---

## Future Direction

- API-first system interface
- orchestration layer (Temporal-style)
- detection packaging + testing
- pluggable collectors and pipelines

---

## Recent Progress

- MVP validated end-to-end
- Windows + synthetic auth pipeline working
- detection loop operational
- demo flow stable