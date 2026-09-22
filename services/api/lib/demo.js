const { formatEventTimestamp } = require("./core");

function buildSyntheticWindowsFailure(index, burstId, burstCount = 5) {
  const ts = new Date(Date.now() - (burstCount - index - 1) * 250);
  return {
    ts: formatEventTimestamp(ts),
    platform: "windows",
    schema_version: "hayabusa.event.v1",
    ingest_source: "vector-windows-endpoint",
    message: `Synthetic failed login demo burst=${burstId} attempt=${index + 1}`,
    fields: {
      event_type: "login",
      user: "test-user",
      src_ip: "192.168.1.50",
      host: "test-host",
      status: "failure",
      event_id: "4625",
      raw_event_id: "4625",
      logon_type: "3",
      domain: "DEMO",
      auth_method: "ntlm",
      collector_name: "demo-generator",
      source_kind: "windows_auth",
      collector_flavor: "hayabusa-demo-generator",
      environment_tag: "demo",
    },
  };
}

module.exports = {
  buildSyntheticWindowsFailure,
};
