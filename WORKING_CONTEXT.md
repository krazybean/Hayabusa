# WORKING_CONTEXT.md (MVP FOCUSED)

## 1. MVP Goal (Single Sentence)
Hayabusa MVP = a reproducible local stack that ingests real logs (including at least one real Windows host), stores them in ClickHouse, runs basic detections, and produces alerts visible in Grafana.

---

## 2. What MVP IS (Strict Boundary)

The MVP is ONLY:

- Docker Compose stack boots on a clean machine
- Logs flow end-to-end:
  - Fluent Bit / Vector → NATS → ClickHouse
- At least ONE real Windows endpoint successfully onboarded
- Events visible in Grafana dashboards
- Detection rules execute and write to `security.alert_candidates`
- Grafana alert triggers and hits webhook (`alert-sink`)
- Operator can follow a short runbook to verify system health

If all of the above works → MVP is DONE

---

## 3. What MVP IS NOT (Explicit Cuts)

The following are NOT part of MVP:

- ❌ No custom UI (Grafana only)
- ❌ No auth / user system
- ❌ No API layer
- ❌ No clustering / HA (ClickHouse Keeper not required)
- ❌ No compliance / reporting
- ❌ No full Wazuh parity
- ❌ No advanced investigation workflows
- ❌ No enrichment pipelines
- ❌ No polished control plane
- ❌ No multi-endpoint fleet management

If it is not required to prove ingest → detect → alert → it is OUT

---

## 4. Current State (Condensed Reality)

### Working
- Local ingest pipeline (Vector → NATS → ClickHouse)
- ClickHouse storage (`security.events`)
- Grafana dashboards + Prometheus metrics
- Detection engine (basic SQL rules → `alert_candidates`)
- Alert routing via webhook (`alert-sink`)
- Windows ingestion pipeline scaffolding + simulator

### Not Yet Proven
- Real Windows host onboarding (CRITICAL GAP)
- Clean bootstrap reproducibility (fresh machine)
- Stability of detection rules (brittle parsing)

---

## 5. MVP Critical Path (ONLY WORK THAT MATTERS)

### 1. Real Endpoint Proof (BLOCKER)
- Successfully onboard ONE real Windows host
- Validate:
  - events arrive in ClickHouse
  - endpoint appears in activity view
  - detections run against real data

👉 If this fails, nothing else matters

---

### 2. Reproducible Bootstrap
- `docker compose up` works on clean environment
- Pin image versions (no `latest`)
- Smoke test passes reliably

---

### 3. Detection Reliability
- Ensure rules:
  - do not silently fail
  - have minimal validation
- Accept limitations (do NOT overbuild engine)

---

### 4. Alert Flow Validation
- Detection → Grafana alert → webhook → alert-sink
- Confirm end-to-end with real data

---

## 6. Deferred Immediately (Do NOT Touch)

- ClickHouse Keeper / clustering
- Global config system (`configs/global`)
- Endpoint promotion / cutover automation beyond MVP
- Control plane / UI work
- Detection engine redesign
- Investigation UX improvements
- Compliance / reporting features

If you touch these, you are delaying MVP

---

## 7. Remaining Work (MVP Only)

### Large
- Real Windows endpoint onboarding + validation

### Medium
- Bootstrap reproducibility (pinning + cleanup)
- Detection rule hardening (basic validation only)

### Small
- Clarify runbook for operator
- Validate alert routing with real data

---

## 8. Estimated Time to MVP

- Best case: 2 weeks
- Likely: 3–5 weeks
- Worst case: 6+ weeks (if endpoint onboarding is problematic)

---

## 9. Success Criteria (Binary)

MVP is DONE when:

- Fresh machine → stack boots successfully
- Real Windows endpoint sends logs
- Logs visible in Grafana
- Detection fires
- Alert is delivered via webhook
- Operator can verify all steps via runbook

No additional features required

---

## 10. Honest Constraints

- This is a **technical MVP**, not a product
- It proves pipeline viability, not market readiness
- It is acceptable if UX is rough and script-driven
- The goal is **proof**, not polish

---

## 11. Focus Rule (Non-Negotiable)

If a task does NOT directly help:

→ ingest  
→ detect  
→ alert  

It is NOT MVP work and should be ignored