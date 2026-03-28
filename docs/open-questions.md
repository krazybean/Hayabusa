# Open Questions

- What is the canonical normalized event schema versioning model?
- Should Vector remain both local generator and central aggregator for early phases?
- Is NATS required from day one, or only after the first direct Vector -> ClickHouse flow works?
- Should detection move from shell MVP to Go or Python for v1 robustness?
- Should bootstrap alerting use Alertmanager or a custom service later?
- Linear workspace access: how should Codex authenticate against `hayabusa / HAY` instead of `beansocial / BEA`?
