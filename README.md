# Hayabusa

[![Dev MVP Validation](https://github.com/krazybean/Hayabusa/actions/workflows/dev-mvp-validation.yml/badge.svg?branch=dev)](https://github.com/krazybean/Hayabusa/actions/workflows/dev-mvp-validation.yml)
[![docker-compose ready](https://img.shields.io/badge/docker--compose-ready-46f39a?labelColor=0b1718&color=46f39a)](MVP_RUNBOOK.md)
[![License: MIT](https://img.shields.io/github/license/krazybean/Hayabusa?label=license)](LICENSE)

> Self-hosted suspicious-login detection for servers.

Hayabusa is a self-hosted security telemetry MVP focused on detecting suspicious login activity on servers.

- Live site: https://krazybean.github.io/Hayabusa/
- Focus: suspicious login detection on Linux SSH/syslog and one Windows collector lane
- What this is: a small Docker Compose proof of `ingest -> store -> detect -> alert`

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
- a synthetic auth-validation lane that exercises the real normalized auth contract before live collectors are available
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
- synthetic auth events can populate `security.auth_events` without live infrastructure
- one Windows host lane exists via `vector-windows-endpoint`
- a first-party-feeling Windows collector path exists while keeping Vector under the hood
- detections are written to `security.alert_candidates`
- Grafana evaluates alert rules from ClickHouse data
- `alert-sink` receives firing and resolved webhook payloads

## Demo Flow

1. logs enter Hayabusa through Vector from syslog/demo traffic or from the Windows collector via NATS
2. NATS JetStream buffers normalized events before they are stored in ClickHouse
3. the detection service evaluates SQL rules on a schedule
4. detection matches are written to `security.alert_candidates`
5. Grafana fires an alert and `alert-sink` logs the webhook payload

## Current Stack

- `vector`: ingest and normalization for local/syslog traffic
- `collector/linux`: Linux SSH collector template, scripts, and real-host docs using Vector under the hood
- `collector/windows`: Windows collector template, scripts, and real-host docs using Vector under the hood
- `nats` + JetStream: buffer
- `hayabusa-ingest`: minimal NATS-to-ClickHouse writer for normalized events
- `clickhouse`: event storage and query engine
- `detection`: scheduled SQL rule runner
- `grafana`: dashboard and alerting
- `alert-sink`: webhook receiver

## Repository Layout

- `configs/`: service config, rules, and provisioning
- `services/`: small custom runtime code
- `scripts/`: bootstrap, validation, and operator helpers
- `docs/`: architecture notes, runbooks, and the static Pages site

## Quick Start

```bash
docker compose up -d --build
./scripts/smoke-test.sh
```

Open the demo UI at `http://localhost:3000`.

## Daily Dev Cycle

Bring the stack up before coding or testing:

```bash
./scripts/dev-up.sh
```

When you are done, tear it back down without deleting volumes:

```bash
./scripts/dev-down.sh
```

Use [MVP_RUNBOOK.md](MVP_RUNBOOK.md) only when you want a full clean reset.

If first boot is slow:
- Grafana downloads the pinned ClickHouse datasource plugin on startup
- a clean machine therefore needs outbound network access for that plugin unless it is already cached

## Where To Look

- Demo UI: `http://localhost:3000`
- API: `http://localhost:8080`
- Grafana: `http://localhost:3001`
- ClickHouse HTTP: `http://localhost:8123`
- NATS monitor: `http://localhost:8222`
- Vector health: `http://localhost:8686/health`
- Windows collector target: `nats://<host>:4222`
- Legacy Windows forward lane: `tcp://<host>:24225`
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
  "SELECT ts, ingest_source, message, fields FROM security.events ORDER BY ts DESC LIMIT 20 FORMAT PrettyCompact"
```

Latest auth events:

```bash
curl -s http://localhost:8123/ --data-binary \
  "SELECT ts, ingest_source, user, src_ip, host, status, source_kind, raw_event_id FROM security.auth_events ORDER BY ts DESC LIMIT 20 FORMAT PrettyCompact"
```

Load synthetic auth scenarios and inspect the normalized auth view:

```bash
./scripts/load-synthetic-auth.sh --clear --scenario all
./scripts/check-auth-events.sh
```

Detection output:

```bash
curl -s http://localhost:8123/ --data-binary \
  "SELECT ts, alert_type, rule_id, attempt_count, entity_user, entity_src_ip, entity_host, distinct_user_count, distinct_ip_count, reason FROM security.alert_candidates ORDER BY ts DESC LIMIT 20 FORMAT PrettyCompact"
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
- [docs/windows-collector-quickstart.md](docs/windows-collector-quickstart.md): shortest Windows collector demo path
- [collector/linux/docs/linux-collector.md](collector/linux/docs/linux-collector.md): Linux SSH collector install/config/test guide
- [collector/windows/docs/windows-collector.md](collector/windows/docs/windows-collector.md): collector-focused Windows install/config/test guide
- [collector/windows/docs/windows-real-host-test.md](collector/windows/docs/windows-real-host-test.md): short first-live-host Windows test walkthrough
- [collector/windows/bundle/README.md](collector/windows/bundle/README.md): handoff bundle notes for a Windows tester
- [scripts/build-windows-collector-package.sh](scripts/build-windows-collector-package.sh): assemble a zip-ready Windows evaluator bundle in `dist/`
- [docs/public-launch-checklist.md](docs/public-launch-checklist.md): final public repo hygiene and pre-announcement checks
- [docs/canonical-event-schema.md](docs/canonical-event-schema.md): raw event envelope and auth view explanation
- [docs/synthetic-auth.md](docs/synthetic-auth.md): synthetic auth scenarios, loader flow, and validation queries

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
