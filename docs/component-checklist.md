# Component Checklist

## Foundation
- [x] ClickHouse
- [x] ClickHouse Keeper
- [x] NATS JetStream
- [x] Grafana
- [x] Prometheus
- [x] Vector

## Collection
- [x] Fluent Bit
- [x] Windows event collection approach
- [x] Windows lane mTLS enabled in active stack
- [x] Windows endpoint enrollment bundle + cert workflow
- [x] syslog input plan
- [x] test generator plan

## Ingestion / Normalization
- [ ] canonical event schema
- [x] Vector transforms
- [x] local sample pipeline
- [ ] schema versioning

## Transport
- [x] NATS subject/stream naming
- [x] retention rules
- [x] replay strategy

## Storage
- [x] ClickHouse database
- [x] events table
- [x] partition strategy
- [x] retention policy
- [x] storage budget guardrail (1 GiB target)
- [ ] sample query set

## Presentation / Alerting
- [x] Grafana dashboard provisioning
- [x] ClickHouse datasource provisioning
- [x] first Grafana-managed alert rule
- [x] storage-near-budget alert rule
- [x] detection-candidate-driven Grafana alert rule
- [x] notification routing policy and contact points (webhook MVP + dedupe)
- [x] detection-engine-backed alert candidate generation

## Detection
- [x] detection service container in compose
- [x] YAML rule schema + example enabled rule
- [x] first security-focused detection rule (failed-login burst)
- [x] Windows EventID-focused rule pack (auth, lockout, service install, privileged group)
- [x] per-rule cooldown suppression (`cooldown_seconds`)
- [x] alert candidate table (`security.alert_candidates`)
- [x] alert routing and notifications (local router + optional external forwarding)

## Delivery Hygiene
- [x] STATUS.md baseline established
- [x] feature wrap-up policy documented
- [ ] Linear `HAY` team integration active in this workspace context
