# Hayabusa Collector for Linux

Hayabusa Collector for Linux is a narrow collector path for **SSH authentication** telemetry.

It exists to feed the current Hayabusa pipeline with high-signal login events:

```text
Linux auth log -> Vector on host -> NATS -> ClickHouse -> detection -> Grafana -> alert-sink
```

## Scope

- tail `/var/log/auth.log` on Debian/Ubuntu
- tail `/var/log/secure` on RHEL/CentOS
- keep only SSH auth events
- normalize successful and failed logins early
- publish JSON to NATS on `events.auth`

This is not a general Linux log collector.

## Supported SSH Patterns

Failed login:

```text
Failed password for invalid user root from 1.2.3.4 port 22 ssh2
Failed password for user from 1.2.3.4 port 22 ssh2
```

Successful login:

```text
Accepted password for user from 1.2.3.4 port 22 ssh2
Accepted publickey for user from 1.2.3.4 port 22 ssh2
```

## Install and Configure

Run on the Linux host:

```bash
sudo ./collector/linux/scripts/install.sh \
  --nats-url nats://<HAYABUSA_HOST_IP>:4222 \
  --subject events.auth \
  --collector-name $(hostname -s)
```

This prepares:

- `/etc/hayabusa/collector/linux/config/vector.toml`
- `/etc/hayabusa/collector/linux/state/`

If Vector is not installed, the script stops at documented manual-install guidance.

## Validate Locally

```bash
./collector/linux/scripts/test-ingestion.sh
```

This checks:

- supported auth log presence
- recent SSH auth lines
- rendered config presence
- `vector validate` if the binary exists
- NATS connectivity if `nc` is available

## Run Interactively First

```bash
sudo vector --config /etc/hayabusa/collector/linux/config/vector.toml
```

For the first real host, interactive logs are easier to debug than hiding Vector behind a service immediately.

## Example Normalized Event

```json
{
  "ts": "2026-04-09 08:33:37.680",
  "platform": "linux-host",
  "schema_version": "hayabusa.event.v1",
  "ingest_source": "vector-linux-ssh",
  "message": "Apr  9 08:33:37 authhost sshd[440]: Failed password for admin from 203.0.113.77 port 22 ssh2",
  "fields": {
    "event_type": "login",
    "user": "admin",
    "src_ip": "203.0.113.77",
    "host": "authhost",
    "status": "failure",
    "auth_method": "password",
    "source_kind": "linux_ssh",
    "collector_name": "authhost",
    "raw_message": "Apr  9 08:33:37 authhost sshd[440]: Failed password for admin from 203.0.113.77 port 22 ssh2"
  }
}
```

## First Real Host Test

1. Start Hayabusa on the server side:

```bash
./scripts/dev-up.sh
./scripts/apply-clickhouse-migrations.sh
```

2. Start the Linux collector interactively on the Linux host.
3. Generate a few failed SSH logins against that Linux host.
4. Verify events on the Hayabusa host:

```bash
docker compose exec -T clickhouse clickhouse-client --query "
SELECT
  ts,
  ingest_source,
  user,
  src_ip,
  host,
  status,
  message
FROM security.auth_events
WHERE ingest_source = 'vector-linux-ssh'
ORDER BY ts DESC
LIMIT 20
FORMAT PrettyCompact"
```

## Troubleshooting

- **No auth log found**: your distro may store SSH auth elsewhere or rotate aggressively.
- **Permission denied reading logs**: run the collector as root or make sure the Vector process can read the auth log.
- **No SSH activity**: the collector intentionally drops non-auth SSH noise.
- **No `src_ip` field**: this collector assumes standard OpenSSH remote-login lines. Local PAM-only events are intentionally ignored.
- **NATS connectivity fails**: verify `4222/tcp` from the Linux host to the Hayabusa host.
- **Different distro format**: adjust the regex in `collector/linux/vector/vector.toml.tpl` only if your OpenSSH syslog format differs.

## Design Notes

- Parsing is intentionally narrow and readable.
- Noise is dropped early instead of shipping partial records.
- The collector keeps the existing Hayabusa architecture intact: Vector -> NATS -> ClickHouse.
