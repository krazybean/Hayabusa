# Hayabusa

[![Dev MVP Validation](https://github.com/krazybean/Hayabusa/actions/workflows/dev-mvp-validation.yml/badge.svg?branch=dev)](https://github.com/krazybean/Hayabusa/actions/workflows/dev-mvp-validation.yml)
[![docker-compose ready](https://img.shields.io/badge/docker--compose-ready-46f39a?labelColor=0b1718&color=46f39a)](MVP_RUNBOOK.md)
[![License: MIT](https://img.shields.io/github/license/krazybean/Hayabusa?label=license)](LICENSE)

See suspicious activity on your machine in under 60 seconds.

## Quickstart

1. `docker compose up -d --build`
2. run the Windows installer
3. open the UI at `http://localhost:3000`
4. click **Simulate Attack**

Watch a brute-force attack get detected instantly.

## What Is Hayabusa?

Hayabusa is a local-first security detection playground.

It lets you simulate real-world attacks and watch them get detected in real time through a full local pipeline you can run with Docker Compose.

Local-first. No cloud. Built for developers.

## What Happens When You Click "Simulate Attack"?

- a realistic failed login burst is generated
- the event flows through `Vector -> NATS -> hayabusa-ingest -> ClickHouse`
- a SQL detection rule triggers
- an alert appears in the UI

This mirrors how Hayabusa detects a real brute-force login pattern.

## Why Hayabusa?

- No cloud required
- No complex setup
- Immediate feedback
- Built for developers and homelabs

- Live site: https://krazybean.github.io/Hayabusa/
- Core path: `ingest -> store -> detect -> alert`

Today it proves one narrow path end to end with a local Docker Compose stack. It is not a full SIEM, not Wazuh parity, and not an enterprise security platform.

## Demo

The **Simulate Attack** flow publishes a synthetic Windows failed-login burst into the live pipeline. That means:

- events are generated with the same normalized auth schema as real collector traffic
- they move through NATS, `hayabusa-ingest`, ClickHouse, and the SQL detection runner
- the UI then shows a **Failed Login Burst Detected** alert

What that alert represents:

- a short burst of failed logins against a Windows endpoint
- the kind of pattern you would want to notice quickly in a homelab or local test machine
- a guided first-success experience, not a fake mockup

## What Hayabusa Detects Right Now

- repeated failed SSH-style login activity from syslog/demo traffic
- repeated failed Windows logons from one real Windows host lane
- synthetic failed login bursts for instant local demos
- endpoint activity visibility from the events already stored in ClickHouse

## Who It Is For

- developers who want to see security detections happen locally
- homelab users who want a practical playground instead of a giant security stack
- self-hosters who prefer a local-first, no-cloud setup

## What It Is Not

- not a full SIEM
- not an enterprise SOC workflow tool
- not a compliance platform
- not multi-tenant
- not HA or clustered
- not trying to replace cloud security products

## Core Experience

1. start the stack with Docker Compose
2. run the Windows collector installer on a local or lab machine
3. open the UI
4. click **Simulate Attack**
5. watch Hayabusa detect it instantly

## Proven Today

- syslog and demo events arrive in `security.events`
- synthetic auth events populate `security.auth_events` without external tools
- one Windows host lane exists via `vector-windows-endpoint`
- a first-party-feeling Windows collector path exists while keeping Vector under the hood
- detections are written to `security.alert_candidates`
- the UI provides a guided first alert via **Simulate Attack**
- Grafana evaluates alert rules from ClickHouse data
- `alert-sink` receives firing and resolved webhook payloads

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
- `scripts/`: bootstrap, validation, packaging, and operator helpers
- `docs/`: runbooks, architecture notes, and the static Pages site

## Try It In 60 Seconds

```bash
docker compose up -d --build
```

Then open:

```text
http://localhost:3000
```

Click **Simulate Attack**.

Hayabusa will generate a realistic failed-login burst, push it through the live pipeline, and show the resulting alert in the UI within a few seconds.

For a real Windows host, build the collector package and run the installer from an elevated PowerShell session:

```bash
./scripts/build-windows-collector-package.sh
```

```powershell
.\install.ps1 `
  -NatsUrl "nats://<HAYABUSA_HOST_IP>:4222" `
  -Subject "security.events" `
  -CollectorName "windows-test-01"
```

## Product Direction

Hayabusa is now explicitly homelab-first and developer-first.

That means:

- optimize for time-to-first-value
- keep onboarding guided and obvious
- avoid enterprise feature creep
- prefer local demos over abstract platform promises

This is not a dashboard. This is a guided first-success experience.

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
- [docs/canonical-event-schema.md](docs/canonical-event-schema.md): raw event envelope and auth view explanation
- [docs/synthetic-auth.md](docs/synthetic-auth.md): synthetic auth scenarios, loader flow, and validation queries
- [SECURITY.md](SECURITY.md): how to report vulnerabilities responsibly

## Deferred Scope

- enterprise security team workflows
- compliance/reporting
- auth, user accounts, and RBAC
- multi-tenant control-plane features
- clustering or HA
- endpoint fleet management beyond one real Windows host path
- advanced control-plane workflows
- external alert routing beyond the local webhook sink

## Repo Pointers

- [docker-compose.yml](docker-compose.yml)
- [configs/vector/vector.yaml](configs/vector/vector.yaml)
- [services/detection/run.sh](services/detection/run.sh)
- [configs/grafana/provisioning/alerting/hayabusa-alerting.yaml](configs/grafana/provisioning/alerting/hayabusa-alerting.yaml)
- [scripts/smoke-test.sh](scripts/smoke-test.sh)
