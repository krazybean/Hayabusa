# Technical Debt Register

This file tracks accepted engineering debt that is intentionally not hidden behind roadmap language.

| Item | Risk | Current mitigation | Exit condition |
| --- | --- | --- | --- |
| API is intentionally minimal | Single-process built-in Node HTTP server has limited structure and no authentication. | Loopback host binding by default, bounded CORS, no raw dependency errors to clients, unit tests for helper contracts. | Introduce an explicit authenticated API boundary before remote/multi-user operation. |
| NATS collector ingress is unauthenticated in MVP | LAN-exposed NATS can accept untrusted publishers if used outside a trusted network. | Documented trust boundary and explicit bind configuration. | Add supported NATS credentials/TLS onboarding for non-local deployments. |
| No HA/clustering | Single-host failure stops detection. | Scope is explicitly local-first MVP. | Address only if product requirements move beyond single-host/self-hosted use. |
| Limited failure-injection coverage | Happy-path E2E is stronger than dependency-failure coverage. | Dependency health checks and retry behavior exist. | Add automated NATS/ClickHouse outage and recovery scenarios. |

Debt is removed from this file when the exit condition is met. New debt that changes correctness, security, or architectural boundaries must be recorded here rather than left implicit.


## Resolved in the anti-vibe hardening pass

- Detection execution semantics moved from the shell runtime into a typed Go service.
- Unit tests now cover detection thresholding, suppression rendering, row parsing, rule enablement, and fingerprint stability.
- Positive and negative synthetic scenarios validate the shipped SQL rules in CI.
