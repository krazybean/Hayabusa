# Canonical Event Schema

Hayabusa uses a stable canonical normalized event contract for `security.events`.

## Active Contract

- Schema ID: `hayabusa.event`
- Active version: `v1`
- Version string: `hayabusa.event.v1`
- Contract file: `configs/global/event-schema-v1.yaml`

## Stable Anchor Columns

`security.events` uses these stable anchors:

- `ts`
- `event_id`
- `platform`
- `schema_version`
- `ingest_source`
- `message`
- `fields`

Source-specific attributes remain in `fields` (`Map(String, String)`).

## Runtime Behavior

- Vector stamps each normalized event with `schema_version = "hayabusa.event.v1"`.
- Vector also writes `fields['schema_version']` for map-level compatibility.
- ClickHouse stores `schema_version` as a first-class column.

## Migration Path (Existing Deployments)

Apply idempotent schema migrations:

```bash
./scripts/apply-clickhouse-migrations.sh
```

This currently ensures:
- `security.events.schema_version` exists with default `hayabusa.event.v1`.

## Validation Queries

Verify column exists:

```bash
curl -s http://localhost:8123 --data-binary \
  "SELECT name, type FROM system.columns WHERE database='security' AND table='events' AND name='schema_version' FORMAT PrettyCompact"
```

Verify recent versions:

```bash
curl -s http://localhost:8123 --data-binary \
  "SELECT schema_version, count() AS events FROM security.events GROUP BY schema_version ORDER BY events DESC FORMAT PrettyCompact"
```

## Versioning Rules

- Breaking changes (anchor remove/rename/type-semantic break) require a new major schema version (for example `v2`).
- Non-breaking additions in `fields` do not require a major version bump.
