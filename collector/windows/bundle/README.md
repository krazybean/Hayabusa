# Hayabusa Collector for Windows

This bundle installs the Hayabusa Windows Collector on a real Windows host.

It is:

- a Windows service installer for Hayabusa auth telemetry
- Vector under the hood
- focused on Windows Security log auth events
- designed to start automatically and send events to Hayabusa

It is not:

- a fleet manager
- a custom Windows agent
- an MSI/GUI installer

## Bundle Contents

```text
hayabusa-windows-collector/
  README.md
  env.example
  install.ps1
  start.ps1
  stop.ps1
  status.ps1
  uninstall.ps1
  validate.ps1
  test-ingestion.ps1
  collect-sample-events.ps1
  emit-security-events.ps1
  vector/vector.toml.tpl
  docs/
```

## Quick Install

Open PowerShell as Administrator from the extracted bundle directory:

```powershell
.\install.ps1 `
  -NatsUrl "nats://192.168.1.109:4222" `
  -Subject "security.events" `
  -CollectorName "windows-test-01" `
  -Environment "lab"
```

The installer:

- creates `C:\ProgramData\HayabusaCollector`
- downloads or stages `vector.exe`
- downloads NSSM and registers `HayabusaCollector` as a Windows service
- renders `vector.toml`
- starts the service automatically

No global execution policy changes are made. The service invokes PowerShell with `-ExecutionPolicy Bypass` only for the collector scripts.

Expected success output:

```text
✔ Installed vector
✔ Configured collector
✔ Service registered
✔ Service started
✅ Hayabusa Collector is running and sending events
```

## Validate

```powershell
.\status.ps1
.\validate.ps1 -NatsUrl "nats://192.168.1.109:4222"
.\collect-sample-events.ps1
```

Generate or inspect `4624` / `4625` events, then confirm rows arrive in Hayabusa with:

- `./scripts/windows-endpoint-check.sh`
- ClickHouse queries against `security.auth_events`

Stop or remove the collector:

```powershell
.\stop.ps1
.\uninstall.ps1
```

## How Windows events are collected

This bundle uses the official Vector Windows build with the supported `exec` source.

Vector runs `emit-security-events.ps1`, which reads recent `4624` / `4625` events from the Security log via `Get-WinEvent` and emits JSON lines for normalization.

Transformed events are also written locally to:

```text
C:\ProgramData\HayabusaCollector\logs\windows-auth-normalized.jsonl
```

If this file receives JSON rows, the helper output made it through Vector normalization. If the file is empty but the helper emits JSON manually, check Vector stderr for remap errors.

If Vector connects but no rows arrive, run:

```powershell
& "C:\ProgramData\HayabusaCollector\scripts\emit-security-events.ps1" -LookbackMinutes 60 -MaxEvents 200 -DebugSummary
```

The debug counters explain whether events were dropped because of unsupported logon types or missing usernames.

For validation, prefer remote SMB or RDP authentication that produces logon type `3` or `10` with a real username. Local lock/unlock, service, and cached logons often produce low-value logon types `5`, `7`, or `11`; those are dropped by design.

## Bundle Build

From the Hayabusa repo:

```bash
./scripts/build-windows-collector-package.sh
```

This creates:

- `dist/hayabusa-windows-collector/`
- `dist/hayabusa-windows-collector.zip` when `zip` is available

For the full walkthrough, see:

- `..\docs\windows-real-host-test.md`
- `..\docs\windows-collector.md`
