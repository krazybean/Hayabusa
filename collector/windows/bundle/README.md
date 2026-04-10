# Hayabusa Collector for Windows Test Bundle

This bundle is the first practical handoff for testing Hayabusa on a real Windows host.

It is:

- a preconfigured Windows collector wrapper for Hayabusa
- Vector under the hood
- focused on Windows Security log auth events
- meant for first-host validation and troubleshooting

It is not:

- a production installer
- a fleet manager
- a custom Windows agent

## Bundle Contents

```text
bundle/
  README.md
  env.example
  install.ps1
  start.ps1
  stop.ps1
..\vector\vector.toml.tpl
..\vector\README.md
..\scripts\install.ps1
..\scripts\configure.ps1
..\scripts\validate.ps1
..\scripts\collect-sample-events.ps1
..\scripts\emit-security-events.ps1
..\scripts\start.ps1
..\scripts\stop.ps1
..\scripts\uninstall.ps1
```

## Quick Use

1. Install or stage `vector.exe` on the Windows host.
2. Run `install.ps1` to create `C:\ProgramData\HayabusaCollector`.
3. Run `configure.ps1` with the Hayabusa NATS URL if you did not already pass it to `install.ps1`.
4. Run `validate.ps1`.
5. Start the collector with `start.ps1` or run Vector interactively with the rendered `vector.toml`.
6. Generate or inspect `4624` / `4625` events.
7. Confirm rows arrive in Hayabusa with:
   - `./scripts/windows-endpoint-check.sh`
   - ClickHouse queries against `security.auth_events`
8. Stop it with `stop.ps1` and clean up with `uninstall.ps1` if needed.

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
.\emit-security-events.ps1 -LookbackMinutes 60 -MaxEvents 200 -DebugSummary
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
