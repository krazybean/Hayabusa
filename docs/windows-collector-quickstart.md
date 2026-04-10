# Windows Collector Quickstart

Goal: get one real Windows auth event into Hayabusa in a few minutes.

This is a test/evaluator path, not a production installer. Vector runs under the hood.

## 1. Start Hayabusa

On the Hayabusa host:

```bash
docker compose up -d --build
```

Expected:

```text
clickhouse        running / healthy
nats              running / healthy
hayabusa-ingest   running
api               running / healthy
web               running / healthy
```

Open:

- Demo UI: http://localhost:3000
- API health: http://localhost:8080/health
- Grafana: http://localhost:3001

## 2. Build the Windows Collector Bundle

On the Hayabusa host:

```bash
./scripts/build-windows-collector-package.sh
```

Copy this file to the Windows machine:

```text
dist/hayabusa-windows-collector.zip
```

Extract it, then open PowerShell as Administrator in the extracted folder.

## 3. Configure the Collector

Replace `<HAYABUSA_HOST_IP>` with the IP address of the machine running Docker Compose:

```powershell
Set-ExecutionPolicy -Scope Process Bypass

.\install.ps1 `
  -NatsUrl "nats://<HAYABUSA_HOST_IP>:4222" `
  -NatsSubject "security.events" `
  -CollectorName "windows-test-01" `
  -EnvironmentTag "demo"
```

Expected output includes:

```text
[hayabusa-collector] Rendered collector config.
Config path      : C:\ProgramData\HayabusaCollector\config\vector.toml
Subject          : security.events
```

## 4. Validate Locally

```powershell
.\validate.ps1
```

Expected:

- Security log is readable
- Vector is found or a clear missing-Vector message is printed
- NATS host/port is reachable
- recent `4624` / `4625` events are visible or guidance is printed

If Vector is missing, install Vector for Windows or place `vector.exe` under:

```text
C:\ProgramData\HayabusaCollector\bin\vector.exe
```

## 5. Start the Collector

```powershell
.\start.ps1
```

Expected:

```text
[hayabusa-collector] Starting Vector in the background.
Debug events: C:\ProgramData\HayabusaCollector\logs\windows-auth-normalized.jsonl
```

## 6. Generate a Useful Failed Login

Best signal comes from remote SMB or RDP activity that creates logon type `3` or `10`.

From another machine, attempt a bad login to the Windows host, or use a remote SMB/RDP login attempt with a real username and bad password.

Local lock/unlock and service logons often create logon types `5`, `7`, or `11`; Hayabusa drops those by design because they are noisy for this demo.

## 7. Confirm the Event Reached Hayabusa

On the Windows machine, confirm Vector normalized the event:

```powershell
Get-Content "C:\ProgramData\HayabusaCollector\logs\windows-auth-normalized.jsonl" -Tail 5
```

On the Hayabusa host:

```bash
curl -s http://localhost:8080/events | jq
```

Or query ClickHouse directly:

```bash
curl -s http://localhost:8123/ --data-binary \
  "SELECT ts, user, src_ip, host, status, raw_event_id FROM security.auth_events WHERE source_kind='windows_auth' ORDER BY ts DESC LIMIT 10 FORMAT PrettyCompact"
```

## 8. See Alerts

Open:

```text
http://localhost:3000
```

If a detection threshold is met, the alert appears in the Alerts table.

For the specific Windows failed-logon burst rule, generate enough failed Windows logons within the rule window, then wait for the detection poll interval.

## Troubleshooting

- No debug JSON file rows:
  run `.\emit-security-events.ps1 -LookbackMinutes 120 -MaxEvents 200 -DebugSummary` and check drop counters.
- Debug JSON exists but no UI rows:
  verify `nats://<HAYABUSA_HOST_IP>:4222` is reachable and `hayabusa-ingest` is running.
- No username or source IP:
  use remote SMB/RDP auth; local logons often omit useful source IPs.
- API works but UI is empty:
  call `http://localhost:8080/events` and `http://localhost:8080/alerts` directly.
- Still stuck:
  check `docker compose logs hayabusa-ingest api vector detection`.
