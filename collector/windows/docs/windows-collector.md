# Hayabusa Collector for Windows

Hayabusa Collector for Windows is a first-party-feeling test bundle for a real Windows host.

It keeps Vector under the hood and preserves the existing Hayabusa pipeline:

```text
Windows Security Log -> Vector on Windows -> NATS -> ClickHouse -> detection -> Grafana -> alert-sink
```

## What This Bundle Is

- a real-host validation path for Windows login telemetry
- a wrapper around Vector, not a custom agent
- focused on `4624` and `4625`
- aligned to Hayabusa's normalized auth contract

## What It Is Not

- not a production installer
- not fleet management
- not a Windows service framework
- not a direct Windows -> ClickHouse path

## Bundle Layout

```text
collector/windows/
  bundle/
    README.md
    env.example
  vector/
    vector.toml.tpl
  scripts/
    install.ps1
    configure.ps1
    validate.ps1
    start.ps1
    stop.ps1
    collect-sample-events.ps1
    test-ingestion.ps1
    uninstall.ps1
  docs/
    windows-collector.md
    windows-real-host-test.md
```

## What The Collector Emits

The collector writes into Hayabusa's current canonical event envelope:

- top level:
  - `ts`
  - `platform`
  - `schema_version`
  - `ingest_source`
  - `message`
  - `fields`
- auth-normalized `fields`:
  - `event_type = login`
  - `user`
  - `src_ip`
  - `host`
  - `status`
  - `source_kind = windows_auth`
  - `raw_event_id`
  - `logon_type`
  - `domain`
  - `auth_method`
  - `collector_name`

`security.auth_events` then flattens those auth fields for detections and investigations.

## Supported Windows Signals

The template intentionally stays narrow:

- `4624` successful logon
- `4625` failed logon
- logon types `2`, `3`, and `10`

Notes:

- `3` and `10` are usually the most useful for suspicious remote logins
- local lock/unlock, service, and cached logons often produce logon types `5`, `7`, or `11` and are intentionally dropped
- events with missing usernames or `TargetUserName = '-'` are intentionally dropped
- some local or system logons will not include a meaningful remote IP
- the collector drops unrelated Security noise on purpose
- the collector uses a PowerShell helper plus Vector's supported `exec` source because the official Windows build does not expose a native `windows_event_log` source

## Practical Flow

1. Start Hayabusa on the host:
   - `./scripts/dev-up.sh`
   - `./scripts/apply-clickhouse-migrations.sh`
2. On Windows, run:
   - `install.ps1`
   - `configure.ps1`
   - `validate.ps1`
3. Start the collector:
   - `start.ps1`
4. Or run Vector interactively:
   - `vector --config "C:\ProgramData\HayabusaCollector\config\vector.toml"`
5. Generate or identify recent `4624` / `4625` events
6. Validate on the Hayabusa host with:
   - `./scripts/windows-endpoint-check.sh`
   - queries against `security.auth_events`
   - queries against `security.alert_candidates`

## Sample Normalized Event

```json
{
  "ts": "2026-04-09 08:33:37.680",
  "platform": "windows",
  "schema_version": "hayabusa.event.v1",
  "ingest_source": "vector-windows-endpoint",
  "message": "Windows logon failure user=admin src_ip=203.0.113.77 host=WIN-ENDPOINT-01 event_id=4625",
  "fields": {
    "event_type": "login",
    "user": "admin",
    "src_ip": "203.0.113.77",
    "host": "WIN-ENDPOINT-01",
    "status": "failure",
    "raw_event_id": "4625",
    "event_id": "4625",
    "logon_type": "3",
    "domain": "LAB",
    "auth_method": "ntlm",
    "collector_name": "WIN-ENDPOINT-01",
    "source_kind": "windows_auth",
    "collector_flavor": "hayabusa-collector-windows",
    "environment_tag": "lab"
  }
}
```

## Common Pitfalls

- no admin rights:
  Security log access may fail unless PowerShell is elevated
- no remote IP:
  some logon types do not populate `IpAddress`; that is normal
- no recent auth events:
  use `collect-sample-events.ps1` and create repeated failed auth attempts
- no events emitted even though `4624` / `4625` exist:
  run `emit-security-events.ps1 -LookbackMinutes 60 -MaxEvents 200 -DebugSummary` and check drop counters
- Vector validates but nothing arrives:
  run it interactively and look for NATS connectivity or sink errors
- too much local noise:
  focus your testing on network or RDP-style logons where possible

## Next Docs

- [windows-real-host-test.md](windows-real-host-test.md)
- [../../../WINDOWS_REAL_HOST_RUNBOOK.md](../../../WINDOWS_REAL_HOST_RUNBOOK.md)
