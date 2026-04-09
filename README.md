# Hayabusa

> Self-hosted suspicious-login detection for servers.

Hayabusa is a self-hosted security telemetry MVP focused on detecting suspicious login activity on servers.

```text
ingest -> store -> detect -> alert
```

Today it proves one narrow path end to end with a local Docker Compose stack. It is not a finished product, not a full SIEM, and not Wazuh parity.

## What Hayabusa Detects Right Now

- repeated failed SSH-style login activity from syslog/demo traffic
- repeated failed Windows logons from one real Windows host lane
- endpoint activity visibility from the events already stored in ClickHouse

## What It Is

- a reproducible stack for log ingestion, buffering, storage, SQL detections, Grafana alerting, and webhook delivery
- a technical proof that suspicious-login telemetry can move from raw events to real alerts
- a base that can support both product direction and setup/integration services later

## Who It Is For

- engineers who want a self-hosted proof of suspicious-login detection
- security consultants who need a credible demoable baseline
- small teams evaluating a focused ClickHouse-based telemetry path

## What It Is Not

- not a full SIEM
- not Wazuh parity
- not a control plane
- not multi-tenant
- not HA or clustered
- not a polished user-facing product

## Proven Today

- syslog and demo events arrive in `security.events`
- one Windows host lane exists via `vector-windows-endpoint`
- detections are written to `security.alert_candidates`
- Grafana evaluates alert rules from ClickHouse data
- `alert-sink` receives firing and resolved webhook payloads

## Demo Flow

1. logs enter Vector from syslog, demo traffic, or one Windows forward lane
2. Vector buffers through NATS JetStream and stores normalized events in ClickHouse
3. the detection service evaluates SQL rules on a schedule
4. detection matches are written to `security.alert_candidates`
5. Grafana fires an alert and `alert-sink` logs the webhook payload

## Current Stack

- `vector`: ingest and normalization
- `nats` + JetStream: buffer
- `clickhouse`: event storage and query engine
- `detection`: scheduled SQL rule runner
- `grafana`: dashboard and alerting
- `alert-sink`: webhook receiver

## Quick Start

```bash
docker compose up -d --remove-orphans
./scripts/smoke-test.sh
```

If first boot is slow:
- Grafana downloads the pinned ClickHouse datasource plugin on startup
- a clean machine therefore needs outbound network access for that plugin unless it is already cached

## Where To Look

- Grafana: `http://localhost:3000`
- ClickHouse HTTP: `http://localhost:8123`
- NATS monitor: `http://localhost:8222`
- Vector health: `http://localhost:8686/health`
- Windows forward lane: `tcp://<host>:24225`
- Alert sink health: `http://localhost:5678/health`

## Lightweight Demo Surface

- static site entry: [docs/index.html](docs/index.html)
- GitHub Pages-ready assets: [docs/styles.css](docs/styles.css)
- local preview:

```bash
python3 -m http.server 8088 -d docs
```

Then open `http://localhost:8088`.

## Verify The MVP

Stored events:

```bash
curl -s http://localhost:8123/ --data-binary \
  "SELECT ts, ingest_source, message FROM security.events ORDER BY ts DESC LIMIT 20 FORMAT PrettyCompact"
```

Detection output:

```bash
curl -s http://localhost:8123/ --data-binary \
  "SELECT ts, rule_id, severity, hits FROM security.alert_candidates ORDER BY ts DESC LIMIT 20 FORMAT PrettyCompact"
```

Webhook delivery:

```bash
docker compose logs --tail=120 alert-sink
```

Expected:
- `received method=POST path=/alerts/default`

## Runbooks

- [MVP_RUNBOOK.md](MVP_RUNBOOK.md): safe project-only reset, clean rebuild, and MVP validation
- [WINDOWS_REAL_HOST_RUNBOOK.md](WINDOWS_REAL_HOST_RUNBOOK.md): first real Windows host onboarding and validation

## Deferred Scope

- authentication and user accounts
- API layer
- custom frontend
- clustering or HA
- compliance/reporting
- endpoint fleet management beyond one real Windows host path
- advanced control-plane workflows
- external alert routing beyond the local webhook sink

## Repo Pointers

- [docker-compose.yml](docker-compose.yml)
- [configs/vector/vector.yaml](configs/vector/vector.yaml)
- [services/detection/run.sh](services/detection/run.sh)
- [configs/grafana/provisioning/alerting/hayabusa-alerting.yaml](configs/grafana/provisioning/alerting/hayabusa-alerting.yaml)
- [scripts/smoke-test.sh](scripts/smoke-test.sh)
