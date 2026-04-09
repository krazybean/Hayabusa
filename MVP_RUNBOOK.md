# Hayabusa MVP Runbook

This runbook is for one demonstration only:

```text
ingest -> store -> detect -> alert
```

## Startup

Use the pinned stack:

```bash
docker compose up -d --remove-orphans
docker compose ps
```

Expected:
- `clickhouse`, `nats`, `vector`, `grafana`, `detection`, and `alert-sink` are `running`
- `nats-init` exits with code `0`

Note:
- on first boot, Grafana may take an extra minute to download `grafana-clickhouse-datasource@4.14.0`
- on first boot, Grafana needs outbound network access to fetch that pinned plugin unless the image cache already has it

## End-to-End Validation

Run:

```bash
./scripts/smoke-test.sh
```

Expected output includes:

```text
OK: ClickHouse
OK: Vector
OK: Alert Router
OK: Grafana
OK: Detection service
OK: JetStream stream present (HAYABUSA_EVENTS)
OK: JetStream consumer present (VECTOR_CLICKHOUSE_WRITER)
OK: events ingested into ClickHouse
OK: detection wrote alert candidate rows
OK: Grafana sent webhook alert to alert-sink
Smoke test passed.
```

Note:
- after a fresh restart, the alert step can take a full Grafana evaluation cycle before the webhook POST appears

## Manual Validation

Check stored events:

```bash
curl -s http://localhost:8123/ --data-binary \
  "SELECT ts, ingest_source, message FROM security.events ORDER BY ts DESC LIMIT 10 FORMAT PrettyCompact"
```

Expected:
- recent rows exist
- `ingest_source` shows `vector-demo_logs` or `vector-syslog`

Check detection output:

```bash
curl -s http://localhost:8123/ --data-binary \
  "SELECT ts, rule_id, severity, hits FROM security.alert_candidates ORDER BY ts DESC LIMIT 10 FORMAT PrettyCompact"
```

Expected:
- recent rows exist
- `rule_id` includes `security_failed_login_burst`

Check webhook delivery:

```bash
docker compose logs --tail=120 alert-sink
```

Expected:
- `received method=POST path=/alerts/default`
- payload includes `security_failed_login_burst`
- after the alert window closes, a second payload appears with `status":"resolved"`

## Alert Trigger Shortcut

If you want to trigger the path manually without the full smoke test:

```bash
for i in 1 2 3 4 5 6; do
  printf '<134>1 %s authhost sshd 10%d ID47 - Failed password for invalid user root from 10.0.0.%d port 22 ssh2\n' "$(date -u +"%Y-%m-%dT%H:%M:%SZ")" "$i" "$i" \
    | nc -u -w1 127.0.0.1 1514
  sleep 1
done
```

Then watch:

```bash
docker compose logs --tail=120 alert-sink
```

## Deferred Until Post-MVP

These are intentionally out of scope for the demo stack:

- Prometheus
- ClickHouse Keeper
- Fluent Bit runtime path
- Windows endpoint collection and endpoint management
- investigation workflows
- compliance or reporting work
- extra detection packs
- extra alert routes beyond the local webhook sink
- any external forwarding requirement

## Most Likely Issues

- Grafana is healthy late on first boot:
  wait for the pinned ClickHouse plugin download to finish, then rerun `./scripts/smoke-test.sh`
- `docker compose` warns about orphan containers:
  run `docker compose up -d --remove-orphans`
