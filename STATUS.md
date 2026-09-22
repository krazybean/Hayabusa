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

- minimal API exists but is not yet a stable/authenticated public contract
- detection runtime remains shell-heavy and lacks isolated rule fixture coverage
- orchestration is implicit (scripts + cron style)
- logic spread across configs + services
- no clear extensibility interface yet

---

## Immediate Priorities

1. complete the anti-vibe hardening pass
2. move detection runtime responsibilities out of shell while preserving SQL rules
3. add isolated detection fixtures and failure-mode tests
4. formalize authenticated API/security boundaries before remote use
5. keep architecture/status documentation synchronized

---

## Deferred Scope

- multi-tenant support
- auth / RBAC
- clustering / HA
- enterprise workflows
- external alert routing

---

## Future Direction

- formalized API-first system interface (building on the existing MVP facade)
- orchestration layer (Temporal-style)
- detection packaging + testing
- pluggable collectors and pipelines

---

## Recent Progress

- MVP validated end-to-end
- Windows + synthetic auth pipeline working
- detection loop operational
- demo flow stable