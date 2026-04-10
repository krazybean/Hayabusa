# Hayabusa MVP Runbook

This runbook is for the current technical MVP only:

```text
ingest -> store -> detect -> alert
```

## 0. Daily Dev Workflow

For normal coding or testing, bring the stack up before work:

```bash
./scripts/dev-up.sh
```

When you are done, tear it down without deleting volumes:

```bash
./scripts/dev-down.sh
```

Use the full reset below only when you want to wipe project containers, volumes, and generated local state.

## 1. Safe Project Reset

This reset is scoped to the Hayabusa repo only.

Stop and remove project containers, network, and volumes:

```bash
docker compose down -v --remove-orphans
```

Remove generated local state used by this repo:

```bash
rm -rf dist/windows-endpoints
rm -rf secrets/windows-forward-tls
find data/host-logs -maxdepth 1 -type f ! -name '.gitkeep' -delete
find data/synthetic-auth -maxdepth 1 -type f ! -name '.gitkeep' -delete
```

Confirm the environment is clean:

```bash
docker compose ps --all
docker volume ls --filter label=com.docker.compose.project=hayabusa
find dist -maxdepth 2 -type f | sort
find data/host-logs -maxdepth 1 -type f ! -name '.gitkeep' | sort
find data/synthetic-auth -maxdepth 1 -type f ! -name '.gitkeep' | sort
test ! -d secrets/windows-forward-tls && echo "windows-forward-tls cleared"
```

Expected:
- `docker compose ps --all` shows no running Hayabusa containers
- no Hayabusa Compose volumes remain
- `dist/windows-endpoints` is empty or absent
- only `data/host-logs/.gitkeep` remains under `data/host-logs`
- only `data/synthetic-auth/.gitkeep` remains under `data/synthetic-auth`
- `secrets/windows-forward-tls` is absent

If old volumes from a pre-MVP stack still appear, remove them explicitly:

```bash
docker volume rm hayabusa_keeper_data hayabusa_prometheus_data
```

## 2. Clean Rebuild

Start the pinned stack:

```bash
docker compose up -d --remove-orphans
./scripts/apply-clickhouse-migrations.sh
docker compose ps
```

Expected:
- `clickhouse`, `nats`, `vector`, `hayabusa-ingest`, `grafana`, `detection`, and `alert-sink` are `running`
- `nats-init` exits with code `0`

First boot note:
- Grafana downloads `grafana-clickhouse-datasource@4.14.0`
- a clean machine therefore needs outbound network access for that step unless the plugin is already cached

## 3. End-to-End MVP Validation

Run:

```bash
./scripts/smoke-test.sh
```

Expected output includes:

```text
OK: ClickHouse
OK: Vector
OK: hayabusa-ingest
OK: Hayabusa API
OK: Hayabusa Web
OK: Alert Router
OK: Grafana
OK: Detection service
OK: JetStream stream present (HAYABUSA_EVENTS)
OK: JetStream consumer present (HAYABUSA_INGEST)
OK: events ingested into ClickHouse
OK: detection wrote alert candidate rows
OK: Grafana sent webhook alert to alert-sink
Smoke test passed.
```

Note:
- after a fresh restart, the alert step can take a full Grafana evaluation cycle before the webhook POST appears

## 4. Manual Checks

Stored events:

```bash
curl -s http://localhost:8123/ --data-binary \
  "SELECT ts, ingest_source, message, fields FROM security.events ORDER BY ts DESC LIMIT 10 FORMAT PrettyCompact"
```

Expected:
- recent rows exist
- `ingest_source` includes `vector-demo_logs` or `vector-syslog`

Latest auth events:

```bash
curl -s http://localhost:8123/ --data-binary \
  "SELECT ts, ingest_source, user, src_ip, host, status, source_kind, raw_event_id FROM security.auth_events ORDER BY ts DESC LIMIT 10 FORMAT PrettyCompact"
```

Expected:
- recent rows exist when auth traffic is present
- `user`, `src_ip`, and `status` are queryable without unpacking `fields`

Synthetic auth validation:

```bash
./scripts/load-synthetic-auth.sh --clear --scenario all
./scripts/check-auth-events.sh
```

Expected:
- `security.events` shows `ingest_source = 'synthetic-auth'`
- `security.auth_events` shows flattened `user`, `src_ip`, `status`, and `source_kind`
- scenarios like `password-spray` and `fail-then-success` are visible in the raw envelope via `fields['scenario']`

Detection output:

```bash
curl -s http://localhost:8123/ --data-binary \
  "SELECT ts, rule_id, severity, hits FROM security.alert_candidates ORDER BY ts DESC LIMIT 10 FORMAT PrettyCompact"
```

Expected:
- recent rows exist
- `rule_id` includes `security_failed_login_burst`

Webhook delivery:

```bash
docker compose logs --tail=120 alert-sink
```

Expected:
- `received method=POST path=/alerts/default`
- payload includes `security_failed_login_burst`
- after the alert window closes, a second payload appears with `status":"resolved"`

## 5. Deferred Scope

These are intentionally outside the current demo:

- Prometheus
- ClickHouse Keeper
- auth or user accounts
- API layer
- custom frontend
- clustering or HA
- compliance/reporting
- endpoint fleet management
- external alert routing beyond the local webhook sink

## 6. Most Likely Issues

- Grafana is healthy late on first boot:
  wait for the pinned plugin download to finish, then rerun `./scripts/smoke-test.sh`
- `docker compose` warns about orphan containers:
  rerun with `docker compose up -d --remove-orphans`
- old generated files still exist after reset:
  rerun the three cleanup commands from section 1 and confirm the directory checks are empty
