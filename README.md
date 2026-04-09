# Hayabusa Strict MVP

Hayabusa is a local Docker Compose proof-of-function stack for one path only:

```text
ingest -> store -> detect -> alert
```

This repo is intentionally narrow. It proves that logs can enter the system, land in ClickHouse, trigger a SQL detection, and produce a webhook alert.

## Active stack

- ClickHouse
- NATS JetStream
- Vector
- Grafana
- detection
- alert-sink

## Quick start

```bash
docker compose up -d --remove-orphans
./scripts/smoke-test.sh
```

Or use:

```bash
./scripts/bootstrap.sh
```

For repeatable demo steps and expected outputs, use `MVP_RUNBOOK.md`.

First boot note:
- Grafana downloads the pinned ClickHouse datasource plugin on startup, so a clean machine needs outbound network access for that step unless the plugin is already cached

## Endpoints

- Grafana: `http://localhost:3000`
- ClickHouse: `http://localhost:8123`
- NATS monitor: `http://localhost:8222`
- Vector health: `http://localhost:8686/health`
- Alert sink: `http://localhost:5678/health`

## External syslog

Vector accepts syslog on:

- `127.0.0.1:1514/tcp`
- `127.0.0.1:1514/udp`

Example:

```bash
printf '<134>1 %s authhost sshd 101 ID47 - Failed password for invalid user root from 10.0.0.1 port 22 ssh2\n' "$(date -u +"%Y-%m-%dT%H:%M:%SZ")" \
  | nc -u -w1 127.0.0.1 1514
```

## Verify each stage

Events in ClickHouse:

```bash
curl -s http://localhost:8123 --data-binary \
  "SELECT ts, ingest_source, message FROM security.events ORDER BY ts DESC LIMIT 20 FORMAT PrettyCompact"
```

Detection output:

```bash
curl -s http://localhost:8123 --data-binary \
  "SELECT ts, rule_id, severity, hits FROM security.alert_candidates ORDER BY ts DESC LIMIT 20 FORMAT PrettyCompact"
```

Webhook delivery:

```bash
docker compose logs --tail=80 alert-sink
```

You should see `received method=POST path=/alerts/default` after the Grafana rule fires.

## Repo shape

- `docker-compose.yml`: strict MVP runtime
- `configs/vector/vector.yaml`: ingestion and buffering
- `configs/rules/mvp/security-failed-login-burst.yaml`: single active rule
- `services/detection/run.sh`: SQL detection loop
- `services/alert-router/server.js`: webhook receiver
- `scripts/smoke-test.sh`: end-to-end verification

## Optional external forwarding

```bash
HAYABUSA_EXTERNAL_WEBHOOK_URL=https://example-alert-endpoint.local/webhook
HAYABUSA_EXTERNAL_WEBHOOK_TOKEN=replace_me
```

If unset, `alert-sink` still logs the Grafana payload locally, which is enough for MVP proof.
