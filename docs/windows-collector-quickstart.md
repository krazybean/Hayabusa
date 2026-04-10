# Windows Collector Quickstart

Goal: see suspicious activity on your machine in under 60 seconds, then validate a real Windows host lane.

Vector runs under the hood. The installer creates a Hayabusa Collector service so the Windows host starts forwarding auth events automatically.

## New Quick Start Flow

1. Start the Hayabusa stack.
2. Open the UI: http://localhost:3000
3. Click **Simulate Attack**.
4. Watch Hayabusa detect the simulated brute-force pattern.
5. Build and copy the Windows collector package.
6. Run the Windows installer as Administrator.
7. Trigger or wait for real Windows failed-login events to validate the collector path.

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

## 2. Prove The Demo Path Without External Tools

Open:

```text
http://localhost:3000
```

Click:

```text
Simulate Attack
```

Expected:

- the API publishes a synthetic Windows failed-login burst to NATS
- `hayabusa-ingest` writes those events into ClickHouse
- the detection service writes an alert candidate shortly after its next poll
- the UI shows a highlighted alert card and expands the details automatically

This proves the local pipeline without SMB/RDP or any external client machine.

## 3. Build the Windows Collector Bundle

On the Hayabusa host:

```bash
./scripts/build-windows-collector-package.sh
```

Copy this file to the Windows machine:

```text
dist/hayabusa-windows-collector.zip
```

Extract it, then open PowerShell as Administrator in the extracted folder.

## 4. Install the Collector

Replace `<HAYABUSA_HOST_IP>` with the IP address of the machine running Docker Compose:

```powershell
.\install.ps1 `
  -NatsUrl "nats://<HAYABUSA_HOST_IP>:4222" `
  -Subject "security.events" `
  -CollectorName "windows-test-01" `
  -Environment "demo"
```

Expected output includes:

```text
✔ Installed vector
✔ Configured collector
✔ Service registered
✔ Service started
✅ Hayabusa Collector is running and sending events
```

The installer does not change global execution policy. It runs collector scripts with `-ExecutionPolicy Bypass` only for the service invocation.

## 5. Validate Locally

```powershell
.\status.ps1
.\validate.ps1
```

Expected:

- Security log is readable
- Vector is installed under `C:\ProgramData\HayabusaCollector\bin`
- `HayabusaCollector` service is running
- NATS host/port is reachable
- recent `4624` / `4625` events are visible or guidance is printed

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

If a detection threshold is met, the alert appears in the Alerts view.

For the specific Windows failed-logon burst rule, generate enough failed Windows logons within the rule window, then wait for the detection poll interval.

You can always click **Simulate Attack** in the UI to prove the alert path without generating real Windows failures.

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
