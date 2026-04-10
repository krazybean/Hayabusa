# Synthetic Auth Validation

Hayabusa keeps the generic `demo_logs` source for transport smoke tests, but that stream is not rich enough to validate the suspicious-login wedge.

This synthetic auth lane exists so you can exercise the real pipeline now:

```text
synthetic file -> Vector normalization -> NATS -> ClickHouse -> detections -> Grafana/webhook
```

It is intentionally labeled with `ingest_source = 'synthetic-auth'` and `collector_name = 'hayabusa-sim'` so it does not get confused with real Windows or Linux collectors.

## What It Covers

The bundled scenarios currently model:

- password spray: one source IP failing against multiple usernames
- fail then success: repeated failures followed by success for one account
- distributed attack: one account targeted from multiple IPs
- benign success: normal successful logins that should not necessarily alert

The records mimic Linux SSH and Windows auth behavior closely enough to validate the auth normalization contract and the current login detections.

## Scenario Files

- `configs/synthetic-auth/scenarios/password-spray.jsonl`
- `configs/synthetic-auth/scenarios/fail-then-success.jsonl`
- `configs/synthetic-auth/scenarios/distributed-attack.jsonl`
- `configs/synthetic-auth/scenarios/benign-success.jsonl`

The scenario content is deterministic. The loader stamps each replay with current UTC timestamps so the existing short-window detections can evaluate the events immediately.

## Load Synthetic Auth Data

Start the stack first:

```bash
./scripts/dev-up.sh
./scripts/apply-clickhouse-migrations.sh
```

Load all scenarios:

```bash
./scripts/load-synthetic-auth.sh --clear --scenario all
```

Load one scenario only:

```bash
./scripts/load-synthetic-auth.sh --clear --scenario password-spray
```

List available scenarios:

```bash
./scripts/load-synthetic-auth.sh --list
```

## Validate Raw vs Normalized Data

Use the helper:

```bash
./scripts/check-auth-events.sh
```

Filter to Linux SSH auth only:

```bash
./scripts/check-auth-events.sh --source-kind linux_ssh
```

Filter to one user or IP:

```bash
./scripts/check-auth-events.sh --user analyst
./scripts/check-auth-events.sh --src-ip 198.51.100.25
```

## Sample ClickHouse Queries

Latest raw synthetic auth rows from the canonical envelope:

```bash
curl -s http://localhost:8123/ --data-binary \
  "SELECT ts, ingest_source, message, fields FROM security.events WHERE ingest_source = 'synthetic-auth' ORDER BY ts DESC LIMIT 20 FORMAT PrettyCompact"
```

Latest normalized auth rows:

```bash
curl -s http://localhost:8123/ --data-binary \
  "SELECT ts, platform, user, src_ip, host, status, source_kind, raw_event_id, auth_method FROM security.auth_events WHERE ingest_source = 'synthetic-auth' ORDER BY ts DESC LIMIT 20 FORMAT PrettyCompact"
```

Password spray style activity:

```bash
curl -s http://localhost:8123/ --data-binary \
  "SELECT src_ip, uniqExact(user) AS targeted_users, count() AS failures FROM security.auth_events WHERE ingest_source = 'synthetic-auth' AND status = 'failure' GROUP BY src_ip HAVING targeted_users >= 3 ORDER BY failures DESC FORMAT PrettyCompact"
```

## Detection Validation

Wait at least one detection poll interval, then check:

```bash
./scripts/recent-detections.sh --lookback-minutes 15
```

Expected detections from the bundled scenarios include:

- `security_source_multi_user_burst` -> `alert_type = password_spray`
- `security_user_multi_source_burst` -> `alert_type = distributed_attack`
- `security_failed_then_success` -> `alert_type = fail_then_success`

Depending on which scenarios you loaded, `security_failed_login_burst` may also appear.

Inspect the explainable alert candidates directly:

```bash
curl -s http://localhost:8123/ --data-binary \
  "SELECT ts, alert_type, alert_fingerprint, window_bucket, attempt_count, entity_user, entity_src_ip, entity_host, distinct_user_count, distinct_ip_count, reason, evidence_summary FROM security.alert_candidates ORDER BY ts DESC LIMIT 20 FORMAT PrettyCompact"
```

Check that repeated detection runs are stable:

```bash
./scripts/check-alert-stability.sh --lookback-minutes 60
```

Expected:
- each intended scenario produces one alert fingerprint per alert window bucket
- rerunning the detector without new data does not create duplicate rows for the same fingerprint
- duplicate fingerprint and duplicate entity/window sections stay empty
- if you intentionally replay the scenario later with fresh timestamps, it can produce a new bucket and a new alert candidate

## Why This Exists

- generic demo/syslog traffic proves transport health
- synthetic auth traffic proves semantic auth normalization
- real Windows/Linux collectors can later replace the synthetic lane without changing the downstream schema or detections
