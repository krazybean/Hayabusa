# Investigation Playbooks (MVP)

These playbooks turn current Hayabusa detections into repeatable analyst actions.
They are mapped to:

- Grafana dashboard: `Hayabusa Investigations`
- Query pack: `docs/investigation-query-pack.md`

## Common Triage Flow

1. Confirm the fired rule in Grafana (`Alerting -> Alert rules`) and capture trigger timestamp.
2. Open `Dashboards -> Hayabusa -> Hayabusa Investigations` and set time range to at least `now-6h to now`.
3. Start with panel `Recent Detection Candidates`, then pivot by `rule_id`, host (`fields['computer']`), and nearest event timestamps.
4. Run targeted SQL from `docs/investigation-query-pack.md` in ClickHouse for raw evidence.
5. Record disposition (`true positive`, `benign`, `needs tuning`) and proposed suppression/tuning action.

## Playbook A: Failed Logon Burst

Use when rules such as `security_failed_login_burst` or `windows_failed_logon_event_burst` trigger.

1. Dashboard pivots:
   - `Failed Logons by Host (60m)`
   - `Recent Windows Endpoint Events`
   - `Recent Detection Candidates`
2. SQL pivots:
   - Query `#2` Failed logon volume by host (last 60m)
   - Query `#1` Latest endpoint security events
3. Decision:
   - If concentrated to one host/user and followed by lockout/service-install/group-change, escalate as likely attack progression.
   - If broad and expected (lab load test), mark benign and consider threshold/cooldown tuning.

## Playbook B: Failed Logon Followed by Lockout

Use when `windows_failed_logon_followed_by_lockout` triggers.

1. Dashboard pivots:
   - `Correlated Lockout Candidates (4625 -> 4740)`
   - `Recent Windows Endpoint Events`
2. SQL pivots:
   - Query `#6` Correlated lockout candidates (4625 -> 4740 within 10m)
   - Query `#1` Latest endpoint security events
3. Decision:
   - If repeated lockout chains occur on critical hosts, escalate immediately and isolate host/account path.
   - If single-user typo patterns dominate without additional suspicious events, classify as likely benign and monitor.

## Playbook C: Service Install or Privileged Group Change Chains

Use when rules below trigger:

- `windows_failed_logon_followed_by_service_install`
- `windows_lockout_followed_by_service_install`
- `windows_failed_logon_followed_by_privileged_group_change`

1. Dashboard pivots:
   - `Windows Detection Triggers Over Time`
   - `Recent Detection Candidates`
   - `Recent Windows Endpoint Events`
2. SQL pivots:
   - Query `#4` Service install events
   - Query `#5` Privileged group membership changes
   - Query `#8` Latest detection candidates
3. Decision:
   - Treat service-install or privileged-group changes following auth anomalies as high-priority.
   - Capture host, user, event IDs, and sequence timing for response handoff.

## Playbook D: Ingest/Telemetry Health Alerts

Use when ingest-health/storage alerts trigger (`Hayabusa Ingest Stalled`, storage-near-budget).

1. Validate service health:
   - `./scripts/smoke-test.sh`
   - `./scripts/storage-budget-guard.sh`
2. Inspect ingest volume:
   - Query `#7` Top ingest sources by event volume (last 60m)
   - Query `#10` Storage footprint check
3. Review pipeline logs:
   - `docker compose logs --tail=120 vector`
   - `docker compose logs --tail=120 fluent-bit`
4. Decision:
   - If ingest source drops to zero unexpectedly, open incident and restore collector path.
   - If storage approaches budget, reduce synthetic generation rate and/or tighten retention.

## Analyst Note Template

Capture the following for each investigation:

- `rule_id` and alert name
- first seen / last seen timestamps
- affected hosts/users
- correlated event IDs
- disposition (`TP`, `benign`, `tuning-needed`)
- follow-up action (block/isolate/tune rule/cooldown update)
