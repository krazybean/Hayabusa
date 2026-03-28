# CLAUDE.md — Hayabusa

## Project overview

Hayabusa is a self-hosted, mostly offline, FOSS-first security telemetry platform. It is a modular alternative to Wazuh built around open-source infrastructure tools. The canonical pipeline is:

```
collect -> normalize -> buffer -> store -> detect -> alert -> investigate
```

## Hard constraints

- Self-hosted only — no cloud-managed dependencies
- FOSS-first — no paid SaaS services
- Docker Compose first — no Kubernetes in the initial implementation
- One service per container
- YAML is the source-of-truth for human-authored config
- Secrets must never appear in version-controlled YAML
- No OpenSearch / Elasticsearch
- Design for later clustering and horizontal scaling, but do not implement it yet

## Approved tool stack

| Role | Tool |
|---|---|
| Event store | ClickHouse |
| Distributed coordination | ClickHouse Keeper |
| Message broker / buffer | NATS JetStream |
| Data collection & transform | Vector |
| Dashboards | Grafana |
| Metrics | Prometheus |

Do not introduce additional services or frameworks unless there is a clear reason. Prefer official upstream images.

## Repository layout

```
configs/         # All service configuration files, organized per service
docs/            # Architecture docs, MVP plan, component checklist, open questions
scripts/         # Bootstrap and utility shell scripts
docker-compose.yml
AGENTS.md        # Project intent and repo behavior guidelines (authoritative)
```

Custom service code (when written) goes in clearly named service directories at the repo root.

## Current state (as of project start)

- Phases 1–5 are structurally complete for the local MVP scaffold
- Vector normalizes demo logs and writes to:
  - ClickHouse table `security.events`
  - console sink for local debug visibility
- NATS is running but not yet wired into the flow
- Detection rules directory exists but no engine is implemented

## Open questions (resolve before implementing affected areas)

1. What is the canonical normalized event schema versioning model?
2. Should Vector serve as both local generator and central aggregator in MVP?
3. Is NATS required before the first direct Vector → ClickHouse path works?
4. Should the first detection engine be written in Go or Python?
5. Should bootstrap alerting use Alertmanager or a custom service?

## Working guidelines

Follow `AGENTS.md` as the authoritative source for repo behavior. Summary:

1. Prefer small, incremental changes
2. Keep file names and directories predictable
3. Add comments to config where they improve readability
4. Preserve modular segment boundaries described in `docs/architecture.md`
5. Expose health checks where practical
6. Keep local deployment simple

When proposing schema or pipeline changes, verify they are consistent with the existing `configs/` files before writing new ones.
