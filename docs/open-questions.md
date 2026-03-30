# Open Questions

- Should Vector remain both local generator and central aggregator for early phases?
- Should JetStream stream retention differ by environment (dev vs prod-like)?
- What triggers a `hayabusa.event.v2` bump (and how should dual-read compatibility be handled)?
- What is the endpoint certificate rotation/revocation strategy for Windows forward mTLS?
- What should be the source-of-truth model for endpoint policy/drift tracking (YAML registry, DB-backed control plane, or hybrid)?
- Should detection move from shell MVP to Go or Python for v1 robustness?
- Should bootstrap alerting use Alertmanager or a custom service later?
- Linear workspace access: how should Codex authenticate against `hayabusa / HAY` instead of `beansocial / BEA`?
