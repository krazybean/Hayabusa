const http = require("http");

const { createClickHouseClient } = require("./lib/clickhouse");
const { limitFromUrl, parseAllowedOrigins, parseLimit } = require("./lib/core");
const { buildSyntheticWindowsFailure } = require("./lib/demo");
const { createNatsClient } = require("./lib/nats");

const listenPort = Number(process.env.API_PORT || 8080);
const clickhouseUrl = process.env.CLICKHOUSE_URL || process.env.CLICKHOUSE_ENDPOINT || "http://localhost:8123";
const natsUrl = process.env.NATS_URL || "nats://localhost:4222";
const natsSubject = process.env.NATS_SUBJECT || "security.events";
const defaultLimit = parseLimit(process.env.DEFAULT_LIMIT, 50);
const testBurstCount = parseLimit(process.env.TEST_EVENT_BURST_COUNT, 5);
const demoEndpointsEnabled = process.env.ENABLE_DEMO_ENDPOINTS === "true";
const allowedOrigins = parseAllowedOrigins(
  process.env.CORS_ORIGINS || "http://localhost:3000,http://127.0.0.1:3000",
);

const clickhouse = createClickHouseClient(clickhouseUrl);
const nats = createNatsClient(natsUrl);

function jsonResponse(req, res, status, payload) {
  const body = JSON.stringify(payload);
  const origin = req.headers.origin || "";
  const headers = {
    "content-type": "application/json; charset=utf-8",
    "access-control-allow-methods": "GET, POST, OPTIONS",
    "access-control-allow-headers": "content-type",
    vary: "Origin",
  };
  if (allowedOrigins.has(origin)) {
    headers["access-control-allow-origin"] = origin;
  }
  res.writeHead(status, headers);
  res.end(body);
}

async function handleAlerts(req, res) {
  const limit = limitFromUrl(req.url, defaultLimit);
  const rows = await clickhouse.query(`
SELECT
  ts AS time,
  rule_name,
  severity,
  coalesce(nullIf(entity_host, ''), nullIf(endpoint_id, ''), '') AS endpoint_id,
  coalesce(nullIf(reason, ''), nullIf(evidence_summary, ''), '') AS summary,
  alert_type,
  rule_id,
  attempt_count,
  principal,
  entity_user,
  source_ip,
  entity_src_ip,
  source_kind,
  window_start,
  window_end,
  first_seen_ts,
  last_seen_ts,
  distinct_user_count,
  distinct_ip_count,
  reason,
  evidence_summary,
  details
FROM security.alert_candidates
ORDER BY ts DESC
LIMIT ${limit}
FORMAT JSONEachRow
`);
  jsonResponse(req, res, 200, { alerts: rows });
}

async function handleEvents(req, res) {
  const limit = limitFromUrl(req.url, defaultLimit);
  const rows = await clickhouse.query(`
SELECT
  ts AS time,
  ingest_source,
  user,
  src_ip,
  host,
  status,
  source_kind,
  raw_event_id,
  logon_type,
  auth_method,
  message
FROM security.auth_events
ORDER BY ts DESC
LIMIT ${limit}
FORMAT JSONEachRow
`);
  jsonResponse(req, res, 200, { events: rows });
}

async function handleHealth(req, res) {
  const [natsConnected, clickhouseHealth] = await Promise.all([
    nats.check(),
    clickhouse.query(`
SELECT
  if(count() = 0, '', formatDateTime(max(ts), '%Y-%m-%d %H:%i:%S', 'UTC')) AS last_event_ts,
  countIf(ts > now() - INTERVAL 1 MINUTE) AS ingest_rate
FROM security.auth_events
FORMAT JSONEachRow
`)
      .then((rows) => ({ ok: true, row: rows[0] || {} }))
      .catch(() => ({ ok: false, row: {} })),
  ]);

  const lastEventTs = clickhouseHealth.row.last_event_ts || "";
  jsonResponse(req, res, 200, {
    ok: natsConnected && clickhouseHealth.ok,
    nats_connected: natsConnected,
    clickhouse_connected: clickhouseHealth.ok,
    last_event_ts: lastEventTs,
    ingest_rate: Number(clickhouseHealth.row.ingest_rate || 0),
    collector_status: lastEventTs ? "connected" : "unknown",
    error: clickhouseHealth.ok ? "" : "clickhouse unavailable",
  });
}

async function handleGenerateTestEvent(req, res) {
  const burstId = `demo-${Date.now()}`;
  const events = Array.from(
    { length: testBurstCount },
    (_, index) => buildSyntheticWindowsFailure(index, burstId, testBurstCount),
  );

  for (const event of events) {
    await nats.publish(natsSubject, event);
  }

  jsonResponse(req, res, 202, {
    ok: true,
    subject: natsSubject,
    events_published: events.length,
    message: "Synthetic Windows failed-login burst sent",
    sample: events[events.length - 1],
  });
}

function createServer() {
  return http.createServer(async (req, res) => {
    try {
      if (req.method === "OPTIONS") {
        return jsonResponse(req, res, 204, {});
      }

      const path = new URL(req.url, "http://localhost").pathname;
      if (req.method === "GET" && path === "/health") {
        return await handleHealth(req, res);
      }
      if (req.method === "GET" && path === "/alerts") {
        return await handleAlerts(req, res);
      }
      if (req.method === "GET" && path === "/events") {
        return await handleEvents(req, res);
      }
      if (demoEndpointsEnabled && req.method === "POST" && path === "/generate-test-event") {
        return await handleGenerateTestEvent(req, res);
      }

      jsonResponse(req, res, 404, { error: "not found" });
    } catch (err) {
      console.error(`[api] ${err.message}`);
      jsonResponse(req, res, 500, { error: "internal server error" });
    }
  });
}

if (require.main === module) {
  const server = createServer();
  server.listen(listenPort, "0.0.0.0", () => {
    console.log(`[api] listening on :${listenPort}, clickhouse=${clickhouseUrl}, nats=${natsUrl}, subject=${natsSubject}`);
  });
}

module.exports = {
  createServer,
};
