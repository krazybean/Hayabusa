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

- minimal API exists but is intentionally local-only and is not yet a stable/authenticated public contract
- NATS collector ingress still assumes a trusted network and has no supported credentials/TLS onboarding path
- orchestration is still implicit (service loops + scripts)
- no clear collector/plugin extensibility interface yet

---

## Immediate Priorities

1. keep the hardening baseline green in CI
2. formalize authenticated API/security boundaries before any remote or multi-user use
3. add supported NATS credentials/TLS onboarding for collector ingress
4. keep architecture/status documentation synchronized
5. defer HA, multi-tenancy, and fleet management until product requirements justify them

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
- detection packaging + broader rule fixture coverage
- pluggable collectors and pipelines

---

## Recent Progress

- MVP validated end-to-end
- Windows + synthetic auth pipeline working
- typed Go detection runtime operational
- positive/negative detection scenarios validated in CI
- ClickHouse/NATS outage and recovery exercised in CI
- management surfaces hardened to loopback by default
- engineering invariants, ADRs, release gates, and technical-debt register documented
- demo flow stable