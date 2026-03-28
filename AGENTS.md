# AGENTS.md

## Project intent

Build a self-hosted, mostly offline, FOSS-first security telemetry platform with modular services and clear boundaries. The project should be suitable for a local Docker Compose deployment first, with a path toward clustering and horizontal scale later.

## High-level architecture

```text
collect -> normalize -> buffer -> store -> detect -> alert -> investigate
```

## Hard constraints

- Self-hosted
- Mostly offline
- FOSS-first
- Docker Compose first
- YAML is the source-of-truth for human-authored config
- One service per container
- Keep services modular
- Design for later clustering and horizontal scaling
- No Kubernetes in the initial implementation
- No cloud-managed dependencies
- No OpenSearch / Elasticsearch
- No paid SaaS services

## Initial selected tools

- ClickHouse
- ClickHouse Keeper
- NATS JetStream
- Vector
- Grafana
- Prometheus

## Repo behavior guidelines

When making changes:
1. Prefer small, incremental changes.
2. Keep file names and directories predictable.
3. Add comments to configuration where it improves readability.
4. Do not introduce extra frameworks or services unless there is a clear reason.
5. Keep local deployment simple.
6. Prefer stock official images for infrastructure services.
7. Keep custom code in clearly named service directories.
8. Keep secrets out of version-controlled YAML.
9. Expose health checks where practical.
10. Preserve the modular segment boundaries described in `docs/architecture.md`.
