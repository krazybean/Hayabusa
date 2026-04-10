data_dir = "__STATE_DIR__"

[api]
enabled = true
address = "127.0.0.1:8686"

# Hayabusa Collector for Linux
# This collector is intentionally narrow:
# - tail common OpenSSH auth logs
# - keep only successful and failed SSH auth events
# - normalize early into the same top-level shape used elsewhere in Hayabusa
# - publish JSON to NATS for the existing store -> detect -> alert pipeline

[sources.ssh_auth_logs]
type = "file"
include = ["/var/log/auth.log", "/var/log/secure"]
read_from = "end"
ignore_older_secs = 86400

[transforms.normalize_ssh_auth]
type = "remap"
inputs = ["ssh_auth_logs"]
source = '''
raw_message = to_string!(.message)

parsed = parse_regex(raw_message, r'^(?P<sys_ts>[A-Z][a-z]{2}\s+\d{1,2}\s+\d{2}:\d{2}:\d{2}) (?P<host>[^\s]+) sshd(?:\[(?P<pid>\d+)\])?: (?P<ssh_message>.*)$') ?? null
if parsed == null {
  abort
}

ssh_message = to_string!(parsed.ssh_message)
host = to_string!(parsed.host)
year = format_timestamp!(now(), format: "%Y", timezone: "UTC")
parsed_ts = parse_timestamp(to_string!(parsed.sys_ts) + " " + year, format: "%b %e %T %Y", timezone: "UTC") ?? now()
ts = format_timestamp!(parsed_ts, format: "%Y-%m-%d %H:%M:%S%.3f", timezone: "UTC")

status = ""
auth_method = ""
user = ""
src_ip = ""

failed = parse_regex(ssh_message, r'^Failed (?P<auth_method>\w+) for (?:invalid user )?(?P<user>[^\s]+) from (?P<src_ip>[0-9A-Fa-f:\.]+)(?: port (?P<port>\d+))?') ?? null
accepted = parse_regex(ssh_message, r'^Accepted (?P<auth_method>\w+) for (?P<user>[^\s]+) from (?P<src_ip>[0-9A-Fa-f:\.]+)(?: port (?P<port>\d+))?') ?? null

if failed != null {
  status = "failure"
  auth_method = to_string!(failed.auth_method)
  user = to_string!(failed.user)
  src_ip = to_string!(failed.src_ip)
} else if accepted != null {
  status = "success"
  auth_method = to_string!(accepted.auth_method)
  user = to_string!(accepted.user)
  src_ip = to_string!(accepted.src_ip)
} else {
  abort
}

if user == "" || src_ip == "" {
  abort
}

. = {
  "ts": ts,
  "platform": "linux-host",
  "schema_version": "hayabusa.event.v1",
  "ingest_source": "vector-linux-ssh",
  "message": raw_message,
  "fields": {
    "event_type": "login",
    "user": user,
    "src_ip": src_ip,
    "host": host,
    "status": status,
    "auth_method": auth_method,
    "source_kind": "linux_ssh",
    "collector_name": "__COLLECTOR_NAME__",
    "raw_message": raw_message,
    "schema_version": "hayabusa.event.v1"
  }
}
'''

[sinks.hayabusa_nats]
type = "nats"
inputs = ["normalize_ssh_auth"]
url = "__NATS_URL__"
subject = "__NATS_SUBJECT__"
connection_name = "hayabusa-linux-collector-__COLLECTOR_NAME__"
encoding.codec = "json"
healthcheck.enabled = true
