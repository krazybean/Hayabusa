# Endpoint Management Baseline

Hayabusa now includes a telemetry-derived endpoint visibility baseline for local MVP operations.

This is not full Wazuh-style agent management yet, but it provides:
- endpoint inventory from observed telemetry
- last-seen status (`active` / `idle` / `stale`)
- lane-aware activity counts for triage

## Inventory Source

ClickHouse view:
- `security.endpoint_activity`

Identity precedence:
1. `fields['computer']`
2. `fields['hostname']`
3. `fields['host']`

Rows with unknown endpoint identity are excluded.

## Status Buckets

`status` is computed from `minutes_since_last_seen`:
- `active`: `<= 15`
- `idle`: `<= 60`
- `stale`: `> 60`

These are MVP defaults for local operations and can be tuned later.

## Operational Commands

Show all discovered endpoints:

```bash
./scripts/endpoint-activity-report.sh
```

Focus on Windows lane:

```bash
./scripts/endpoint-activity-report.sh --lane vector-windows-endpoint
```

Fail if no Windows endpoint is visible:

```bash
./scripts/endpoint-activity-report.sh \
  --lane vector-windows-endpoint \
  --min-endpoints 1
```

Fail if any selected endpoint is stale:

```bash
./scripts/endpoint-activity-report.sh \
  --lane vector-windows-endpoint \
  --max-stale-minutes 120
```

## Migration

For existing deployments:

```bash
./scripts/apply-clickhouse-migrations.sh
```

This ensures:
- `security.events.schema_version` column exists
- `security.endpoint_activity` view exists

## Current Scope

Included now:
- telemetry-derived endpoint inventory
- lane-level endpoint visibility
- scriptable stale/offline checks

Still pending for stronger Wazuh parity:
- endpoint policy rollout/update orchestration
- endpoint config drift tracking
- agent lifecycle and centralized policy assignment
