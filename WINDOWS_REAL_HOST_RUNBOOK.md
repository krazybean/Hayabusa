# Windows Real Host Runbook

This runbook proves one real Windows endpoint through the current Hayabusa path:

```text
Windows host -> Fluent Bit winevtlog -> Vector 24225 -> ClickHouse -> detection -> Grafana -> alert-sink
```

## What This Uses

- active Hayabusa stack on the Linux/macOS host
- one real Windows machine
- Fluent Bit on the Windows machine
- no auth, no API, no control-plane workflow
- no mTLS for this first-host proof path

Old mTLS, endpoint policy, and cutover-orchestration scripts existed on `main` history, but they are intentionally not part of the active first-host path on `dev`.

## 1. Start Hayabusa

```bash
docker compose up -d --remove-orphans
./scripts/apply-clickhouse-migrations.sh
docker compose ps
```

Expected:
- `vector` is running
- host port `24225/tcp` is exposed

## 2. Build the Windows bundle

Replace `<HAYABUSA_HOST_IP>` with the IP the Windows machine can reach.

```bash
./scripts/enroll-windows-endpoint.sh \
  --endpoint-id WIN-ENDPOINT-01 \
  --vector-host <HAYABUSA_HOST_IP> \
  --force
```

Expected output:
- `dist/windows-endpoints/WIN-ENDPOINT-01/fluent-bit.conf`
- `dist/windows-endpoints/WIN-ENDPOINT-01/README.txt`

## 3. Install and start Fluent Bit on Windows

Assumption:
- Fluent Bit is installed under `C:\fluent-bit`

Copy this file from the Hayabusa host to the Windows machine:

- `dist/windows-endpoints/WIN-ENDPOINT-01/fluent-bit.conf` -> `C:\fluent-bit\conf\fluent-bit.conf`

Start Fluent Bit interactively first:

```powershell
C:\fluent-bit\bin\fluent-bit.exe -c C:\fluent-bit\conf\fluent-bit.conf
```

Expected:
- Fluent Bit stays running
- no repeated connection errors to `<HAYABUSA_HOST_IP>:24225`

## 4. Verify the host is sending events

On the Hayabusa host:

```bash
./scripts/windows-endpoint-check.sh --computer WIN-ENDPOINT-01
```

Expected:
- event count is `>= 1`
- recent rows show `ingest_source = vector-windows-endpoint`
- `computer`, `channel`, or `event_id` fields are populated

Direct query if needed:

```bash
curl -s http://localhost:8123/ --data-binary \
  "SELECT ts, ingest_source, fields['computer'] AS computer, fields['channel'] AS channel, fields['event_id'] AS event_id, message FROM security.events WHERE ingest_source='vector-windows-endpoint' ORDER BY ts DESC LIMIT 20 FORMAT PrettyCompact"
```

## 5. Verify endpoint visibility

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

## 6. Verify a Windows detection can evaluate

The active Windows rule is `windows_failed_logon_burst`.

Check for candidates:

```bash
curl -s http://localhost:8123/ --data-binary \
  "SELECT ts, rule_id, severity, hits FROM security.alert_candidates WHERE rule_id='windows_failed_logon_burst' ORDER BY ts DESC LIMIT 20 FORMAT PrettyCompact"
```

Expected after a qualifying condition:
- one or more rows with `rule_id = windows_failed_logon_burst`

## 7. Trigger the qualifying condition

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

## 8. Verify the alert chain

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
  check host firewall, reachable Hayabusa IP, and whether Fluent Bit can connect to port `24225`
- rows arrive but `computer` is empty:
  inspect the Windows Fluent Bit output and confirm the `winevtlog` record includes `Computer`
- detection does not fire:
  verify the Windows host actually generated repeated failed logons and check `fields['event_id']='4625'`
- Grafana alert is delayed:
  wait one full Grafana evaluation cycle and recheck `alert-sink`
