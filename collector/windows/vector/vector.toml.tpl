data_dir = "__STATE_DIR__"

[api]
enabled = true
address = "127.0.0.1:8686"

# Hayabusa Collector for Windows
# Official Vector for Windows does not provide a native Windows Event Log source
# in this build, so the collector uses the supported `exec` source and runs a
# small PowerShell helper that emits one JSON line per relevant Security event.
#
# Scope stays intentionally narrow:
# - Security log only
# - 4624 successful logon
# - 4625 failed logon
# - emphasis on logon types useful for suspicious-login detection

[sources.windows_security]
type = "exec"
mode = "scheduled"
command = [
  "powershell.exe",
  "-NoProfile",
  "-ExecutionPolicy",
  "Bypass",
  "-File",
  "__EVENT_EXPORT_SCRIPT__",
  "-StatePath",
  "__EVENT_EXPORT_STATE__",
  "-LookbackMinutes",
  "30",
  "-MaxEvents",
  "200"
]

[sources.windows_security.scheduled]
exec_interval_secs = 15

[transforms.normalize_windows_auth]
type = "remap"
inputs = ["windows_security"]
source = '''
raw_exec_message = to_string(.message) ?? ""
if raw_exec_message == "" {
  raw_exec_message = to_string(.stdout) ?? ""
}

payload = parse_json(raw_exec_message) ?? null
if payload == null {
  abort
}

event_id = to_string(payload.event_id) ?? ""

if event_id != "4624" && event_id != "4625" {
  abort
}

user = to_string(payload.user) ?? ""

domain = to_string(payload.domain) ?? ""

src_ip = to_string(payload.src_ip) ?? ""

if src_ip == "-" || src_ip == "::1" || src_ip == "::ffff:127.0.0.1" {
  src_ip = ""
}

logon_type = to_string(payload.logon_type) ?? ""

auth_method = downcase(to_string(payload.auth_method) ?? "")

host = "__COLLECTOR_NAME__"
payload_host = to_string(payload.host) ?? ""
if payload_host != "" {
  host = payload_host
}

provider_name = to_string(payload.provider_name) ?? ""
record_id = to_string(payload.record_id) ?? ""

status = if event_id == "4624" { "success" } else { "failure" }

# Keep only the higher-signal logon types for the suspicious-login wedge:
# 2  = interactive
# 3  = network
# 10 = remote interactive / RDP
if logon_type != "" && logon_type != "2" && logon_type != "3" && logon_type != "10" {
  abort
}

if user == "" || user == "-" {
  abort
}

environment_tag = "__ENVIRONMENT_TAG__"

timestamp_text = to_string(payload.timestamp) ?? ""
parsed_ts = parse_timestamp(timestamp_text, format: "%+") ?? now()
ts = format_timestamp!(parsed_ts, format: "%Y-%m-%d %H:%M:%S%.3f", timezone: "UTC")

message = "Windows logon " + status + " user=" + user
if src_ip != "" {
  message = message + " src_ip=" + src_ip
}
message = message + " host=" + host + " event_id=" + event_id

raw_details = to_string(payload.raw_message) ?? ""
if raw_details != "" {
  raw_details = replace(raw_details, "\r", " ")
  raw_details = replace(raw_details, "\n", " ")
  message = message + " details=" + raw_details
}

fields = {
  "event_type": "login",
  "user": user,
  "src_ip": src_ip,
  "host": host,
  "status": status,
  "raw_event_id": event_id,
  "event_id": event_id,
  "logon_type": logon_type,
  "domain": domain,
  "auth_method": auth_method,
  "collector_name": "__COLLECTOR_NAME__",
  "source_kind": "windows_auth",
  "collector_flavor": "hayabusa-collector-windows",
  "environment_tag": environment_tag,
  "channel": "Security",
  "provider_name": provider_name,
  "computer": host,
  "record_id": record_id,
  "schema_version": "hayabusa.event.v1"
}

. = {
  "ts": ts,
  "platform": "windows",
  "schema_version": "hayabusa.event.v1",
  "ingest_source": "vector-windows-endpoint",
  "message": message,
  "fields": fields
}
'''

# Local post-transform trace for first-host debugging. This file proves that
# the exec source output survived normalization before the NATS sink publishes.
[sinks.windows_auth_debug]
type = "file"
inputs = ["normalize_windows_auth"]
path = "__DEBUG_OUTPUT_PATH__"
encoding.codec = "json"

[sinks.hayabusa_nats]
type = "nats"
inputs = ["normalize_windows_auth"]
url = "__NATS_URL__"
subject = "__NATS_SUBJECT__"
connection_name = "hayabusa-collector-__COLLECTOR_NAME__"
encoding.codec = "json"
healthcheck.enabled = true
__NATS_AUTH_BLOCK__
