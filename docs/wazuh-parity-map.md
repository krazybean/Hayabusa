# Wazuh Parity Map (Current)

This project targets a modular, self-hosted architecture comparable to Wazuh over time.
Current status is local MVP foundation, not full feature parity yet.

## Parity Snapshot

- Data collection/ingest baseline: **strong-mvp**
- Storage and search baseline: **partial-strong**
- Dashboards and visibility baseline: **partial**
- Detection rules engine: **partial-strong**
- Alert routing and notifications: **partial**
- Endpoint management/agents: **early**
- Investigation workflow tooling: **partial**
- Compliance/reporting workflows: **not started**

## What is already in place

- Core stack running in Docker Compose: ClickHouse, Keeper, NATS, Vector, Prometheus, Grafana
- Active buffered ingest path (`Vector -> NATS JetStream -> ClickHouse`)
- Host collector baseline with Fluent Bit (`tail -> forward -> Vector`)
- Windows event collection strategy defined (`winevtlog -> forward -> Vector:24225`) + validation script
- Windows lane locally validated via simulator traffic (`vector-windows-endpoint`)
- Windows lane mTLS enabled in active stack path (Vector source + Fluent Bit client auth)
- Windows endpoint enrollment bundle workflow with endpoint-specific client cert generation
- Windows real-host cutover guard script (`windows-real-host-cutover-check.sh`) for endpoint-specific validation and CIDR hardening checks
- Normalized events stored in ClickHouse (`security.events`)
- External syslog ingestion over TCP/UDP (`1514`)
- Provisioned Grafana dashboard for event visibility
- First Grafana-managed alert rule for ingest-stall detection
- 1 GiB storage budget guardrail for synthetic event volume
- Detection engine MVP (`YAML -> SQL`) writing to `security.alert_candidates`
- First security-focused detection rule (`security_failed_login_burst`)
- Windows EventID detection pack:
  - `windows_failed_logon_event_burst` (4625)
  - `windows_account_lockout_detected` (4740)
  - `windows_failed_logon_followed_by_lockout` (correlation 4625 -> 4740)
  - `windows_failed_logon_followed_by_service_install` (correlation 4625 -> 4697/7045)
  - `windows_failed_logon_followed_by_privileged_group_change` (correlation 4625 -> 4728/4732/4756)
  - `windows_lockout_followed_by_service_install` (correlation 4740 -> 4697/7045)
  - `windows_service_install_detected` (4697/7045)
  - `windows_privileged_group_membership_change` (4728/4732/4756)
- Detection cooldown controls (`cooldown_seconds`) to reduce repeat-trigger noise
- Detection host/user suppression controls (`suppression_*` + query placeholder integration)
- Investigation query pack with starter SQL hunts (`docs/investigation-query-pack.md`)
- Grafana investigation dashboard (`Hayabusa Investigations`) for one-click pivot queries
- Investigation playbooks mapped to current dashboard/query pivots (`docs/investigation-playbooks.md`)
- Detection-candidate-driven Grafana alert (`Hayabusa Security Failed Login Burst`)
- Grafana correlation alert rules for Windows multi-signal detections
- Alert routing MVP with dedupe policy via Grafana contact points (local router + optional external forwarding with auth token support)
- Alert router external forwarding hardening (timeout + retry/backoff controls)

## Major gaps vs Wazuh-style capabilities

- Endpoint security agents and central policy management
- Built-in detection library and correlation engine
- Case management / investigation workflow tooling
- Notification fan-out strategy (email/webhook/chat/on-call)
- Asset, identity, and threat-intel enrichment pipelines
- Compliance packs and reporting templates
- Detection correlation and built-in content depth comparable to Wazuh rulesets

## Next parity-focused milestones

1. First real Windows host deployment using enrollment bundle (replace simulator-driven validation)
2. Detection tuning wave 2 (threshold calibration + curated suppression lists toward Wazuh depth)
3. Investigation workflow acceleration (case linkage + analyst workflow automation)
4. Alert destination fan-out (email/chat/on-call) + endpoint/agent management model for Wazuh-comparable host visibility
