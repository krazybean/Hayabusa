const http = require("http");

const listenPort = Number(process.env.API_PORT || 8080);
const clickhouseUrl = (process.env.CLICKHOUSE_URL || process.env.CLICKHOUSE_ENDPOINT || "http://localhost:8123").replace(/\/$/, "");
const defaultLimit = parseLimit(process.env.DEFAULT_LIMIT, 50);

function parseLimit(value, fallback = defaultLimit) {
  const parsed = Number(value);
  if (!Number.isFinite(parsed) || parsed < 1) return fallback;
  return Math.min(Math.floor(parsed), 200);
}

function jsonResponse(res, status, payload) {
  const body = JSON.stringify(payload);
  res.writeHead(status, {
    "content-type": "application/json; charset=utf-8",
    "access-control-allow-origin": "*",
    "access-control-allow-methods": "GET, OPTIONS",
    "access-control-allow-headers": "content-type",
  });
  res.end(body);
}

async function queryClickHouse(sql) {
  const resp = await fetch(`${clickhouseUrl}/`, {
    method: "POST",
    body: sql,
  });

  const text = await resp.text();
  if (!resp.ok) {
    throw new Error(`ClickHouse ${resp.status}: ${text.trim()}`);
  }

  return text
    .split("\n")
    .filter(Boolean)
    .map((line) => JSON.parse(line));
}

function limitFromUrl(reqUrl) {
  return parseLimit(new URL(reqUrl, "http://localhost").searchParams.get("limit"));
}

async function handleAlerts(req, res) {
  const limit = limitFromUrl(req.url);
  const rows = await queryClickHouse(`
SELECT
  ts AS time,
  rule_name,
  severity,
  coalesce(nullIf(entity_host, ''), nullIf(endpoint_id, ''), '') AS endpoint_id,
  coalesce(nullIf(reason, ''), nullIf(evidence_summary, ''), '') AS summary,
  alert_type,
  rule_id,
  attempt_count,
  entity_user,
  entity_src_ip,
  source_kind
FROM security.alert_candidates
ORDER BY ts DESC
LIMIT ${limit}
FORMAT JSONEachRow
`);
  jsonResponse(res, 200, { alerts: rows });
}

async function handleEvents(req, res) {
  const limit = limitFromUrl(req.url);
  const rows = await queryClickHouse(`
SELECT
  ts AS time,
  ingest_source,
  user,
  src_ip,
  host,
  status,
  source_kind,
  raw_event_id,
  message
FROM security.auth_events
ORDER BY ts DESC
LIMIT ${limit}
FORMAT JSONEachRow
`);
  jsonResponse(res, 200, { events: rows });
}

const server = http.createServer(async (req, res) => {
  try {
    if (req.method === "OPTIONS") {
      return jsonResponse(res, 204, {});
    }

    const path = new URL(req.url, "http://localhost").pathname;
    if (req.method === "GET" && path === "/health") {
      return jsonResponse(res, 200, { ok: true });
    }
    if (req.method === "GET" && path === "/alerts") {
      return await handleAlerts(req, res);
    }
    if (req.method === "GET" && path === "/events") {
      return await handleEvents(req, res);
    }

    jsonResponse(res, 404, { error: "not found" });
  } catch (err) {
    console.error(`[api] ${err.message}`);
    jsonResponse(res, 500, { error: err.message });
  }
});

server.listen(listenPort, "0.0.0.0", () => {
  console.log(`[api] listening on :${listenPort}, clickhouse=${clickhouseUrl}`);
});
