# Detection Engine MVP

## Goal

Run a simple SQL rule on a fixed schedule and persist matches.

## Current behavior

- Service: `detection` (Docker Compose)
- Input: YAML rule files in `configs/rules/mvp/*.yaml`
- Query target: ClickHouse (`security.events`)
- Output table: `security.alert_candidates`
- Poll interval: `30s` (configurable with `DETECTION_POLL_SECONDS`)
- Active rule: `security_failed_login_burst`
- Grafana reads `security.alert_candidates` and routes firing alerts to `alert-sink`

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
    AND positionCaseInsensitive(message, 'failed password') > 0
```

## Notes

- `query` must return a single integer value.
- If threshold condition matches, a row is inserted into `security.alert_candidates`.
- `cooldown_seconds` suppresses repeat inserts for the same rule during the cooldown window.
- This service is intentionally simple and shell-based. It is not meant to be a full rule engine.

## Quick local test (failed login burst)

Send synthetic failed-login syslog lines:

```bash
for i in 1 2 3 4 5 6; do
  printf '<134>1 %s authhost sshd 10%d ID47 - Failed password for invalid user root from 10.0.0.%d port 22 ssh2\n' "$(date -u +"%Y-%m-%dT%H:%M:%SZ")" "$i" "$i" \
    | nc -u -w1 127.0.0.1 1514
  sleep 1
done
```

Then query candidates:

```bash
curl -s http://localhost:8123 --data-binary \
  "SELECT ts, rule_id, severity, hits FROM security.alert_candidates WHERE rule_id = 'security_failed_login_burst' ORDER BY ts DESC LIMIT 10 FORMAT PrettyCompact"
```
