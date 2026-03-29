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
- [x] Windows real-host cutover guard script (CIDR + endpoint-specific validation)
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
- [x] sample query set

## Presentation / Alerting
- [x] Grafana dashboard provisioning
- [x] investigation dashboard provisioning (`Hayabusa Investigations`)
- [x] ClickHouse datasource provisioning
- [x] first Grafana-managed alert rule
- [x] storage-near-budget alert rule
- [x] detection-candidate-driven Grafana alert rule
- [x] correlation detection alert rules (Windows multi-signal chain alerts)
- [x] notification routing policy and contact points (webhook MVP + dedupe)
- [x] detection-engine-backed alert candidate generation
- [x] alert router retry/backoff + timeout controls for external forwarding

## Detection
- [x] detection service container in compose
- [x] YAML rule schema + example enabled rule
- [x] first security-focused detection rule (failed-login burst)
- [x] Windows EventID-focused rule pack (auth, lockout, service install, privileged group)
- [x] multi-signal Windows correlation rule pack
- [x] per-rule cooldown suppression (`cooldown_seconds`)
- [x] host/user scoped suppression controls (`suppression_*` + `{{SUPPRESSION_CONDITION}}`)
- [x] alert candidate table (`security.alert_candidates`)
- [x] alert routing and notifications (local router + optional external forwarding)

## Investigation Workflow
- [x] investigation query pack (`docs/investigation-query-pack.md`)
- [x] investigation playbooks mapped to dashboard pivots (`docs/investigation-playbooks.md`)

## Delivery Hygiene
- [x] STATUS.md baseline established
- [x] feature wrap-up policy documented
- [ ] Linear `HAY` team integration active in this workspace context
