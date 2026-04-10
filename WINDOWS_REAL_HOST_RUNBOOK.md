# Windows Real Host Runbook

This runbook proves one real Windows endpoint through the current Hayabusa collector path:

```text
Windows Event Log -> Hayabusa Collector for Windows -> NATS -> ClickHouse -> detection -> Grafana -> alert-sink
```

## What This Uses

- active Hayabusa stack on the Linux/macOS host
- one real Windows machine
- Vector on the Windows machine, wrapped in a Hayabusa collector install/config flow
- Vector uses the supported `exec` source on Windows and shells out to a bundled PowerShell Security-log helper
- no auth, no API, no control-plane workflow
- no direct Windows -> ClickHouse shortcut

The detailed collector doc lives at:

- [collector/windows/docs/windows-collector.md](collector/windows/docs/windows-collector.md)
- [collector/windows/docs/windows-real-host-test.md](collector/windows/docs/windows-real-host-test.md)
- [collector/windows/bundle/README.md](collector/windows/bundle/README.md)

## 1. Start Hayabusa

```bash
./scripts/dev-up.sh
./scripts/apply-clickhouse-migrations.sh
```

Expected:
- `nats` is running
- host port `4222/tcp` is exposed

## 2. Install and configure the Windows collector

On the Windows machine, from the cloned repo:

```powershell
Set-ExecutionPolicy -Scope Process Bypass
.\collector\windows\scripts\install.ps1 `
  -NatsUrl "nats://<HAYABUSA_HOST_IP>:4222" `
  -NatsSubject "events.auth" `
  -CollectorName WIN-ENDPOINT-01
```

Expected output:
- `C:\ProgramData\HayabusaCollector\config\vector.toml`
- `C:\ProgramData\HayabusaCollector\README.md`

## 3. Validate locally on Windows

```powershell
.\collector\windows\scripts\validate.ps1
```

Expected:
- Security log is readable
- recent `4624` / `4625` events can be queried
- config is present
- NATS connectivity is testable

## 4. Start the collector

Packaged path:

```powershell
.\collector\windows\scripts\start.ps1
```

Or run Vector directly:

```powershell
vector --config "C:\ProgramData\HayabusaCollector\config\vector.toml"
```

Expected:
- the collector stays running
- no repeated NATS sink errors
- use `.\collector\windows\scripts\collect-sample-events.ps1` in a second PowerShell window if you need help producing or inspecting recent `4624` / `4625` events

## 5. Verify the host is sending events

On the Hayabusa host:

```bash
./scripts/windows-endpoint-check.sh --computer WIN-ENDPOINT-01
```

Expected:
- event count is `>= 1`
- recent rows show `ingest_source = vector-windows-endpoint`
- `computer`, `channel`, `event_id`, or `user` fields are populated

Direct query if needed:

```bash
docker compose exec -T clickhouse clickhouse-client --query "
SELECT
  ts,
  ingest_source,
  host AS computer,
  user,
  src_ip,
  raw_event_id AS event_id,
  status,
  message
FROM security.auth_events
WHERE ingest_source='vector-windows-endpoint'
ORDER BY ts DESC
LIMIT 20
FORMAT PrettyCompact"
```

## 6. Verify endpoint visibility

```bash
./scripts/endpoint-activity-report.sh --lane vector-windows-endpoint --min-endpoints 1
```

Expected:
- one endpoint row is present
- `endpoint_id` shows `WIN-ENDPOINT-01`
- status is `active` or `idle`

Grafana:
- open `http://localhost:3000`
- open `Hayabusa Overview`
- confirm the `Endpoint Activity` table shows the Windows host

## 7. Verify a Windows detection can evaluate

The active Windows rule is `windows_failed_logon_burst`.

Check for candidates:

```bash
curl -s http://localhost:8123/ --data-binary \
  "SELECT ts, rule_id, severity, hits FROM security.alert_candidates WHERE rule_id='windows_failed_logon_burst' ORDER BY ts DESC LIMIT 20 FORMAT PrettyCompact"
```

Expected after a qualifying condition:
- one or more rows with `rule_id = windows_failed_logon_burst`

## 8. Trigger the qualifying condition

Fastest practical path:
- generate repeated failed logons on the Windows machine
- five failures within five minutes should satisfy the rule

Practical test options:
- enter the wrong password repeatedly at the Windows login screen
- or repeat a bad local auth attempt from a shell

Example shell loop on Windows:

```powershell
1..5 | ForEach-Object { cmd /c "net use \\127.0.0.1\IPC$ /user:.\NoSuchUser WrongPass123! >NUL 2>&1" }
```

If the host records `4625` events, the rule should evaluate on the next detection cycle.

## 9. Verify the alert chain

Wait about 30 to 90 seconds, then check:

```bash
curl -s http://localhost:8123/ --data-binary \
  "SELECT ts, rule_id, severity, hits FROM security.alert_candidates WHERE rule_id='windows_failed_logon_burst' ORDER BY ts DESC LIMIT 10 FORMAT PrettyCompact"

docker compose logs --tail=120 alert-sink
```

Expected:
- `security.alert_candidates` contains `windows_failed_logon_burst`
- `alert-sink` logs `received method=POST path=/alerts/default`
- webhook payload includes `windows_failed_logon_burst`

Resolved state:
- once the qualifying window passes, `alert-sink` should also receive a resolved payload

## Most Likely Issues

- no Windows rows arrive:
  check host firewall, reachable Hayabusa IP, and whether the Windows host can reach NATS on `4222`
- rows arrive but `computer` or `user` is empty:
  inspect a local `4624`/`4625` event on the Windows host and compare it to the template assumptions in `collector/windows/vector/vector.toml.tpl`
- detection does not fire:
  verify the Windows host actually generated repeated failed logons and check `fields['event_id']='4625'`
- Grafana alert is delayed:
  wait one full Grafana evaluation cycle and recheck `alert-sink`
