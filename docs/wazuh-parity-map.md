# Wazuh Parity Map (Current)

This project targets a modular, self-hosted architecture comparable to Wazuh over time.
Current status is local MVP foundation, not full feature parity yet.

## Parity Snapshot

- Data collection/ingest baseline: **partial**
- Storage and search baseline: **partial**
- Dashboards and visibility baseline: **partial**
- Detection rules engine: **early**
- Alert routing and notifications: **early**
- Endpoint management/agents: **not started**
- Compliance/reporting workflows: **not started**

## What is already in place

- Core stack running in Docker Compose: ClickHouse, Keeper, NATS, Vector, Prometheus, Grafana
- Normalized events stored in ClickHouse (`security.events`)
- External syslog ingestion over TCP/UDP (`1514`)
- Provisioned Grafana dashboard for event visibility
- First Grafana-managed alert rule for ingest-stall detection
- 1 GiB storage budget guardrail for synthetic event volume
- Detection engine MVP (`YAML -> SQL`) writing to `security.alert_candidates`
- First security-focused detection rule (`security_failed_login_burst`)
- Detection-candidate-driven Grafana alert (`Hayabusa Security Failed Login Burst`)
- Alert routing MVP with dedupe policy via Grafana contact points (local router + optional external forwarding with auth token support)

## Major gaps vs Wazuh-style capabilities

- Endpoint security agents and central policy management
- Built-in detection library and correlation engine
- Case management / investigation workflow tooling
- Notification fan-out strategy (email/webhook/chat/on-call)
- Asset, identity, and threat-intel enrichment pipelines
- Compliance packs and reporting templates
- Detection correlation and built-in content depth comparable to Wazuh rulesets

## Next parity-focused milestones

1. Detection engine MVP (YAML rule -> SQL query -> alert record)
2. Alert routing MVP (contact points + policy + dedupe)
3. NATS in active path for buffering/replay durability
4. Host collector strategy (Fluent Bit + Windows event path)
