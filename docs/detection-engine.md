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
query: |
  SELECT count()
  FROM security.events
  WHERE ts > now() - INTERVAL 1 MINUTE
```

## Notes

- `query` must return a single integer value.
- If threshold condition matches, a row is inserted into `security.alert_candidates`.
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
