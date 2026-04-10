# Windows Real Host Test

This is the shortest practical path for first live validation of the Hayabusa Windows collector bundle.

## Purpose

Prove that one real Windows host can:

1. read Windows Security log auth events
2. normalize them into Hayabusa's auth contract
3. send them through `Vector -> NATS -> ClickHouse`
4. show up in `security.auth_events`
5. feed existing detections and alerts

This bundle uses Vector's supported `exec` source on Windows. A small PowerShell helper reads `4624` / `4625` events with `Get-WinEvent` and emits JSON lines for Vector to normalize.

## Preconditions

- Hayabusa stack is running on the receiving host
- the Windows host can reach `nats://<hayabusa-host>:4222`
- `vector.exe` is installed or available to copy into the bundle

## 1. Start Hayabusa

```bash
./scripts/dev-up.sh
./scripts/apply-clickhouse-migrations.sh
```

## 2. Install the Windows bundle

On the Windows machine:

```powershell
Set-ExecutionPolicy -Scope Process Bypass
.\collector\windows\scripts\install.ps1 `
  -NatsUrl "nats://<HAYABUSA_HOST_IP>:4222" `
  -NatsSubject "security.events" `
  -CollectorName WIN-ENDPOINT-01 `
  -EnvironmentTag lab
```

If Vector is not already installed, either:

- install it normally
- or rerun `install.ps1 -VectorExePath C:\Path\To\vector.exe`

## 3. Validate locally

```powershell
.\collector\windows\scripts\validate.ps1
```

Expected:

- Security log readable
- recent `4624` / `4625` events present
- config file exists
- Vector validates
- NATS endpoint reachable

## 4. Start the collector

Recommended packaged path:

```powershell
.\collector\windows\scripts\start.ps1
```

Or run Vector directly:

```powershell
vector --config "C:\ProgramData\HayabusaCollector\config\vector.toml"
```

Keep this terminal open during the first test.

Vector also writes post-normalization debug rows to:

```text
C:\ProgramData\HayabusaCollector\logs\windows-auth-normalized.jsonl
```

This file should receive one JSON row per qualifying Windows auth event before the NATS sink publishes it.

## 5. Generate or inspect Windows logon activity

Use the helper:

```powershell
.\collector\windows\scripts\collect-sample-events.ps1
```

Practical failed-login loop:

```powershell
1..5 | ForEach-Object { cmd /c "net use \\127.0.0.1\IPC$ /user:.\NoSuchUser WrongPass123! >NUL 2>&1" }
```

Better validation signal comes from remote SMB or RDP authentication that produces logon type `3` or `10` with a real `TargetUserName`. Local lock/unlock, service logons, and cached logons often produce logon types `5`, `7`, or `11`; those are intentionally dropped by this collector path.

If Vector is connected but no events arrive, run the exporter directly with diagnostics:

```powershell
powershell.exe -NoProfile -ExecutionPolicy Bypass `
  -File "C:\ProgramData\HayabusaCollector\scripts\emit-security-events.ps1" `
  -LookbackMinutes 60 `
  -MaxEvents 200 `
  -DebugSummary
```

Expected debug counters include:

- `scanned_4624_4625`
- `dropped_unsupported_logon_type`
- `dropped_missing_or_invalid_username`
- `emitted_records`

## 6. Validate on the Hayabusa host

Recent raw envelope rows:

Optional live NATS check while generating auth activity:

```bash
docker compose run --rm --no-deps nats-init \
  nats --server nats://nats:4222 sub security.events
```

```bash
curl -s http://localhost:8123/ --data-binary \
  "SELECT ts, ingest_source, message, fields FROM security.events WHERE ingest_source = 'vector-windows-endpoint' ORDER BY ts DESC LIMIT 20 FORMAT PrettyCompact"
```

Recent normalized Windows auth rows:

```bash
curl -s http://localhost:8123/ --data-binary \
  "SELECT ts, platform, user, src_ip, host, status, source_kind, raw_event_id, collector_name FROM security.auth_events WHERE ingest_source = 'vector-windows-endpoint' ORDER BY ts DESC LIMIT 20 FORMAT PrettyCompact"
```

Filter by collector:

```bash
curl -s http://localhost:8123/ --data-binary \
  "SELECT ts, user, src_ip, host, status, raw_event_id FROM security.auth_events WHERE collector_name = 'WIN-ENDPOINT-01' ORDER BY ts DESC LIMIT 20 FORMAT PrettyCompact"
```

Check whether detections fired:

```bash
curl -s http://localhost:8123/ --data-binary \
  "SELECT ts, rule_id, alert_type, attempt_count, entity_user, entity_src_ip, entity_host, reason FROM security.alert_candidates WHERE entity_host = 'WIN-ENDPOINT-01' ORDER BY ts DESC LIMIT 20 FORMAT PrettyCompact"
```

## 7. Troubleshooting

- no events in ClickHouse:
  check Vector terminal output first
- helper emits JSON but NATS is empty:
  check `C:\ProgramData\HayabusaCollector\logs\windows-auth-normalized.jsonl`; if it is empty, inspect Vector stderr for remap errors
- Security log unreadable:
  rerun as Administrator
- no `4624` / `4625` rows locally:
  produce a few deliberate auth attempts
- no `src_ip`:
  local logons often omit it; network/RDP logons are better for this test
- exporter scans events but emits zero records:
  check the debug counters for unsupported logon types or `TargetUserName = '-'`
- NATS connectivity failure:
  verify host IP, port `4222`, firewall, and Docker port exposure

## Result

Success means:

- the Windows host contributes rows to `security.events`
- those rows appear in `security.auth_events`
- the collector identity is visible via `collector_name`
- existing detections can evaluate that data
