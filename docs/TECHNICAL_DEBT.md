# Technical Debt Register

This file tracks accepted engineering debt that is intentionally not hidden behind roadmap language.

| Item | Risk | Current mitigation | Exit condition |
| --- | --- | --- | --- |
| API has no authentication | The API is intentionally local-only and must not become a remote or multi-user control plane without authentication/authorization. | Explicit module boundaries, loopback host binding by default, bounded CORS, bounded error responses, and unit/integration validation. | Introduce an explicit authenticated API boundary before remote/multi-user operation. |
| NATS collector ingress is unauthenticated in MVP | LAN-exposed NATS can accept untrusted publishers if used outside a trusted network. | Documented trust boundary and explicit bind configuration. | Add supported NATS credentials/TLS onboarding for non-local deployments. |
| No HA/clustering | Single-host failure stops detection. | Scope is explicitly local-first MVP. | Address only if product requirements move beyond single-host/self-hosted use. |

Debt is removed from this file when the exit condition is met. New debt that changes correctness, security, or architectural boundaries must be recorded here rather than left implicit.


## Resolved in the anti-vibe hardening pass

- Detection execution semantics moved from the shell runtime into a typed Go service.
- Unit tests now cover detection thresholding, suppression rendering, row parsing, rule enablement, and fingerprint stability.
- Positive and negative synthetic scenarios validate the shipped SQL rules in CI.

- Dependency failure/recovery is now exercised in CI for ClickHouse and NATS, including post-recovery event flow.

- API routing, dependency clients, and demo-event generation were separated into explicit modules without adding framework dependencies.
