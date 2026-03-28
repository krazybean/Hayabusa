# Open Questions

- What is the canonical normalized event schema versioning model?
- Should Vector remain both local generator and central aggregator for early phases?
- Should JetStream stream retention differ by environment (dev vs prod-like)?
- Which Windows event collector path should be the default (Fluent Bit winevtlog vs Windows-native exporter)?
- Should detection move from shell MVP to Go or Python for v1 robustness?
- Should bootstrap alerting use Alertmanager or a custom service later?
- Linear workspace access: how should Codex authenticate against `hayabusa / HAY` instead of `beansocial / BEA`?
