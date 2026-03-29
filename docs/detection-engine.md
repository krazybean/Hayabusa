# Detection Engine MVP

## Goal

Run YAML-defined SQL rules on a schedule and persist triggered detections.

## Current behavior

- Service: `detection` (Docker Compose)
- Input: YAML rule files in `configs/rules/detections/*.yaml`
- Query target: ClickHouse (`security.events`)
- Output table: `security.alert_candidates`
- Poll interval: `30s` (configurable with `DETECTION_POLL_SECONDS`)
- Default rules:
  - `mvp_high_event_rate` (fallback surge detector)
  - `security_failed_login_burst` (keyword-based auth failure burst)
  - `windows_failed_logon_event_burst` (Windows EventID 4625 burst)
  - `windows_account_lockout_detected` (Windows EventID 4740)
  - `windows_failed_logon_followed_by_lockout` (correlation: 4625 -> 4740)
  - `windows_service_install_detected` (Windows EventID 4697/7045)
  - `windows_privileged_group_membership_change` (Windows EventID 4728/4732/4756)
- Grafana alert route: detection candidates are routed via notification policy to `alert-sink` (router webhook)

## Rule schema (MVP)

```yaml
id: unique_rule_id
name: Human readable title
description: What the rule detects
severity: low|medium|high|critical
enabled: true|false
threshold_op: gt|gte|eq|lt|lte
threshold_value: 50
cooldown_seconds: 300
query: |
  SELECT count()
  FROM security.events
  WHERE ts > now() - INTERVAL 1 MINUTE
```

## Notes

- `query` must return a single integer value.
- If threshold condition matches, a row is inserted into `security.alert_candidates`.
- `cooldown_seconds` is optional; when set, repeated triggers for the same rule are suppressed during cooldown.
- This is detection-candidate generation only; routing/notification policy is separate work.

## Quick local test (failed login burst)

Send synthetic failed-login syslog lines:

```bash
for i in 1 2 3 4; do
  printf '<134>1 2026-03-28T00:00:00Z authhost sshd 100%d ID47 - Failed password for invalid user root from 10.0.0.%d port 22 ssh2\n' "$i" "$i" \
    | nc -u -w1 127.0.0.1 1514
done
```

Then query candidates:

```bash
curl -s http://localhost:8123 --data-binary \
  "SELECT ts, rule_id, severity, hits FROM security.alert_candidates WHERE rule_id = 'security_failed_login_burst' ORDER BY ts DESC LIMIT 10 FORMAT PrettyCompact"
```

## Quick local test (Windows EventID rules)

Generate Windows security scenario events:

```bash
./scripts/generate-windows-security-scenarios.sh
```

Then query triggered Windows rules:

```bash
curl -s http://localhost:8123 --data-binary \
  "SELECT ts, rule_id, severity, hits FROM security.alert_candidates WHERE rule_id LIKE 'windows_%' ORDER BY ts DESC LIMIT 20 FORMAT PrettyCompact"
```

Then verify correlation rule specifically:

```bash
curl -s http://localhost:8123 --data-binary \
  "SELECT ts, rule_id, severity, hits FROM security.alert_candidates WHERE rule_id = 'windows_failed_logon_followed_by_lockout' ORDER BY ts DESC LIMIT 10 FORMAT PrettyCompact"
```
