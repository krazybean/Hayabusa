# Canonical Event Schema

Hayabusa uses a stable canonical normalized event contract for `security.events`.
For auth-focused detections and investigations, it also exposes a flattened logical view: `security.auth_events`.

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

## Why There Is Also `security.auth_events`

- `security.events` stays flexible for ingestion
- `security.auth_events` keeps login detections readable
- cross-platform auth attributes (`user`, `src_ip`, `host`, `status`) become queryable without repeating `fields[...]` extraction everywhere

This is a targeted seam for the suspicious-login wedge, not a full flattening of every event type.

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
- `security.auth_events` exists as a flattened auth-focused view.

## Validation Queries

Verify the raw envelope schema:

```bash
curl -s http://localhost:8123 --data-binary \
  "SELECT name, type FROM system.columns WHERE database='security' AND table='events' AND name='schema_version' FORMAT PrettyCompact"
```

Inspect raw events:

```bash
curl -s http://localhost:8123 --data-binary \
  "SELECT ts, ingest_source, message, fields FROM security.events ORDER BY ts DESC LIMIT 10 FORMAT PrettyCompact"
```

Inspect flattened auth events:

```bash
curl -s http://localhost:8123 --data-binary \
  "SELECT ts, ingest_source, user, src_ip, host, status, source_kind, raw_event_id FROM security.auth_events ORDER BY ts DESC LIMIT 10 FORMAT PrettyCompact"
```

Linux SSH auth events only:

```bash
curl -s http://localhost:8123 --data-binary \
  "SELECT ts, user, src_ip, host, status, auth_method FROM security.auth_events WHERE source_kind='linux_ssh' ORDER BY ts DESC LIMIT 10 FORMAT PrettyCompact"
```

Windows auth events only:

```bash
curl -s http://localhost:8123 --data-binary \
  "SELECT ts, user, src_ip, host, status, raw_event_id, logon_type FROM security.auth_events WHERE ingest_source='vector-windows-endpoint' ORDER BY ts DESC LIMIT 10 FORMAT PrettyCompact"
```

Synthetic auth events only:

```bash
curl -s http://localhost:8123 --data-binary \
  "SELECT ts, platform, user, src_ip, host, status, source_kind, auth_method FROM security.auth_events WHERE ingest_source='synthetic-auth' ORDER BY ts DESC LIMIT 10 FORMAT PrettyCompact"
```

Investigate one user or source IP:

```bash
curl -s http://localhost:8123 --data-binary \
  "SELECT ts, ingest_source, user, src_ip, host, status, message FROM security.auth_events WHERE user='admin' OR src_ip='203.0.113.77' ORDER BY ts DESC LIMIT 20 FORMAT PrettyCompact"
```

## Versioning Rules

- Breaking changes (anchor remove/rename/type-semantic break) require a new major schema version (for example `v2`).
- Non-breaking additions in `fields` do not require a major version bump.
