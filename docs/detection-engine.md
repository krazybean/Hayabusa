# Detection Engine MVP

## Goal

Run a simple SQL rule on a fixed schedule and persist matches.

## Current behavior

- Service: `detection` (Docker Compose)
- Input: YAML rule files in `configs/rules/mvp/*.yaml`
- Query target for auth rules: ClickHouse (`security.auth_events`)
- Output table: `security.alert_candidates`
- Recent detections view: `security.recent_login_detections`
- Poll interval: `30s` (configurable with `DETECTION_POLL_SECONDS`)
- Active login rules:
  - `security_source_multi_user_burst` -> `alert_type = password_spray`
  - `security_failed_then_success` -> `alert_type = fail_then_success`
  - `security_user_multi_source_burst` -> `alert_type = distributed_attack`
  - `security_failed_login_burst`
  - `windows_failed_logon_burst`
- Grafana reads `security.alert_candidates` and routes firing alerts to `alert-sink`

## Rule schema (MVP)

```yaml
id: unique_rule_id
name: Human readable title
description: What the rule detects
severity: low|medium|high|critical
enabled: true|false
alert_type: password_spray|fail_then_success|distributed_attack
threshold_op: gt|gte|eq|lt|lte
threshold_value: 50
threshold_attempts: 5
threshold_distinct_users: 3
threshold_distinct_ips: 3
threshold_failures: 3
window_minutes: 5
cooldown_seconds: 300
query: |
  SELECT
    count() AS hits,
    '' AS principal,
    '' AS source_ip,
    '' AS endpoint_id,
    min(ts) AS window_start,
    max(ts) AS window_end,
    0 AS distinct_user_count,
    0 AS distinct_ip_count,
    'linux_ssh' AS source_kind,
    'Human-readable reason' AS reason,
    'Short evidence summary' AS evidence_summary,
    'Optional detail payload' AS details
  FROM security.auth_events
  WHERE ts > now() - INTERVAL {{WINDOW_MINUTES}} MINUTE
    AND status = 'failure'
```

## Notes

- `query` should return columns in this order:
  1. `hits`
  2. `principal`
  3. `source_ip`
  4. `endpoint_id`
  5. `window_start`
  6. `window_end`
  7. `distinct_user_count`
  8. `distinct_ip_count`
  9. `source_kind`
  10. `reason`
  11. `evidence_summary`
  12. `details`
  13. `window_bucket`
- `window_minutes` is available as a `{{WINDOW_MINUTES}}` placeholder inside the SQL.
- `threshold_attempts`, `threshold_distinct_users`, `threshold_distinct_ips`, and `threshold_failures` are optional SQL placeholders for the v1.1 suspicious-login rules.
- `security.events` remains the canonical raw envelope table.
- `security.auth_events` is the flattened logical view for auth-focused rules and investigations.
- If threshold condition matches, a row is inserted into `security.alert_candidates`.
- `cooldown_seconds` suppresses repeat inserts for the same alert fingerprint during the cooldown window.
- `window_bucket` is a stable interval bucket derived from the alert window. Rules typically snap `window_end` to the rule's `window_minutes`.
- `alert_fingerprint` is built from `alert_type + entity + source_kind + window_bucket`. This is the current sameness rule for "same incident, same window."
- Repeated detector polls over unchanged data should stay quiet because the fingerprint stays stable inside the same bucket.
- When a materially new cluster lands in a later bucket, Hayabusa emits a new candidate. That behavior is intentional.
- Long-running activity can still emit once per later bucket if the incident keeps extending. Hayabusa treats that as a new alert window, not a duplicate.
- Current practical sameness rules:
  - `password_spray`: same `alert_type + entity_src_ip + entity_host + source_kind + window_bucket`
  - `distributed_attack`: same `alert_type + entity_user + entity_host + source_kind + window_bucket`
  - `fail_then_success`: same `alert_type + entity_user + entity_src_ip + entity_host + source_kind + window_bucket`
- `reason` and `evidence_summary` are meant to explain why the detection fired without opening raw logs.
- `security.alert_candidates` stores operator-facing fields such as `alert_type`, `entity_user`, `entity_src_ip`, `entity_host`, `attempt_count`, `distinct_user_count`, and `distinct_ip_count`.
- This service is intentionally simple and shell-based. It is not meant to be a full rule engine.

## Recent detections query path

Use the helper script for recent explainable detections:

```bash
./scripts/recent-detections.sh --lookback-minutes 60 --limit 10
```

Or query ClickHouse directly:

```bash
curl -s http://localhost:8123 --data-binary \
  "SELECT ts, alert_type, alert_fingerprint, window_bucket, rule_id, attempt_count, entity_user, entity_src_ip, entity_host, distinct_user_count, distinct_ip_count, source_kind, reason, evidence_summary FROM security.recent_login_detections ORDER BY ts DESC LIMIT 10 FORMAT PrettyCompact"
```

Inspect the underlying auth view:

```bash
curl -s http://localhost:8123 --data-binary \
  "SELECT ts, ingest_source, user, src_ip, host, status, source_kind FROM security.auth_events ORDER BY ts DESC LIMIT 10 FORMAT PrettyCompact"
```

## Quick local tests

### 1. Synthetic auth path

Load the deterministic auth scenarios:

```bash
./scripts/load-synthetic-auth.sh --clear --scenario all
```

Then inspect the normalized rows:

```bash
./scripts/check-auth-events.sh --limit 10
```

### 2. Password spray

Load the `password-spray` scenario and inspect:

```bash
./scripts/load-synthetic-auth.sh --clear --scenario password-spray
./scripts/recent-detections.sh --rule-id security_source_multi_user_burst --lookback-minutes 30 --limit 5
```

### 3. Failed logins followed by success

Load the `fail-then-success` scenario and inspect:

```bash
./scripts/load-synthetic-auth.sh --clear --scenario fail-then-success
./scripts/recent-detections.sh --rule-id security_failed_then_success --lookback-minutes 30 --limit 5
```

### 4. Distributed attack

Load the `distributed-attack` scenario and inspect:

```bash
./scripts/load-synthetic-auth.sh --clear --scenario distributed-attack
./scripts/recent-detections.sh --rule-id security_user_multi_source_burst --lookback-minutes 30 --limit 5
```

### 5. Duplicate / stability checks

Show any duplicate alert fingerprints:

```bash
docker compose exec -T clickhouse clickhouse-client --query \
  "SELECT alert_type, alert_fingerprint, count() AS duplicates FROM security.alert_candidates GROUP BY alert_type, alert_fingerprint HAVING duplicates > 1 FORMAT PrettyCompact"
```

Show totals by alert type versus unique fingerprints:

```bash
docker compose exec -T clickhouse clickhouse-client --query \
  "SELECT alert_type, count() AS alerts, uniqExact(alert_fingerprint) AS unique_fingerprints FROM security.alert_candidates GROUP BY alert_type ORDER BY alert_type FORMAT PrettyCompact"
```

Expected:
- no rows from the duplicate-fingerprint query
- `alerts` should match `unique_fingerprints` unless you intentionally inserted historic duplicates before the fingerprint change

Check entity-level duplicates inside the same alert window bucket:

```bash
./scripts/check-alert-stability.sh --lookback-minutes 60
```

Expected:
- duplicate fingerprint and duplicate entity/window sections should be empty
- rerunning the detector without new data should not increase totals inside the same bucket
