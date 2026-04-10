const http = require("http");
const net = require("net");

const listenPort = Number(process.env.API_PORT || 8080);
const clickhouseUrl = (process.env.CLICKHOUSE_URL || process.env.CLICKHOUSE_ENDPOINT || "http://localhost:8123").replace(/\/$/, "");
const natsUrl = process.env.NATS_URL || "nats://localhost:4222";
const natsSubject = process.env.NATS_SUBJECT || "security.events";
const defaultLimit = parseLimit(process.env.DEFAULT_LIMIT, 50);
const testBurstCount = parseLimit(process.env.TEST_EVENT_BURST_COUNT, 5);

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
    "access-control-allow-methods": "GET, POST, OPTIONS",
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

function formatEventTimestamp(date) {
  const pad = (value, size = 2) => String(value).padStart(size, "0");
  return [
    date.getUTCFullYear(),
    pad(date.getUTCMonth() + 1),
    pad(date.getUTCDate()),
  ].join("-") + " " + [
    pad(date.getUTCHours()),
    pad(date.getUTCMinutes()),
    pad(date.getUTCSeconds()),
  ].join(":") + `.${pad(date.getUTCMilliseconds(), 3)}`;
}

function parseNatsEndpoint(value) {
  const parsed = new URL(value);
  if (parsed.protocol !== "nats:") {
    throw new Error(`Unsupported NATS_URL protocol: ${parsed.protocol}`);
  }

  return {
    host: parsed.hostname || "localhost",
    port: Number(parsed.port || 4222),
  };
}

function publishNats(subject, payload) {
  const { host, port } = parseNatsEndpoint(natsUrl);
  const body = Buffer.from(JSON.stringify(payload));
  const command = Buffer.concat([
    Buffer.from(`CONNECT {"verbose":false,"pedantic":false,"lang":"node","version":"hayabusa-demo"}\r\n`),
    Buffer.from(`PUB ${subject} ${body.length}\r\n`),
    body,
    Buffer.from("\r\nPING\r\n"),
  ]);

  return new Promise((resolve, reject) => {
    const socket = net.createConnection({ host, port });
    let buffer = "";
    let sent = false;
    const timeout = setTimeout(() => {
      socket.destroy();
      reject(new Error(`NATS publish timed out for ${host}:${port}`));
    }, 4000);

    socket.on("connect", () => {
      socket.setEncoding("utf8");
    });

    socket.on("data", (chunk) => {
      buffer += chunk;
      if (!sent && buffer.includes("INFO")) {
        sent = true;
        socket.write(command);
      }
      if (buffer.includes("-ERR")) {
        clearTimeout(timeout);
        socket.destroy();
        reject(new Error(buffer.trim()));
      }
      if (buffer.includes("PONG")) {
        clearTimeout(timeout);
        socket.end();
        resolve();
      }
    });

    socket.on("error", (err) => {
      clearTimeout(timeout);
      reject(err);
    });
  });
}

async function checkNats() {
  const { host, port } = parseNatsEndpoint(natsUrl);
  return new Promise((resolve) => {
    const socket = net.createConnection({ host, port });
    const timeout = setTimeout(() => {
      socket.destroy();
      resolve(false);
    }, 1500);

    socket.on("connect", () => {
      clearTimeout(timeout);
      socket.end();
      resolve(true);
    });
    socket.on("error", () => {
      clearTimeout(timeout);
      resolve(false);
    });
  });
}

function buildSyntheticWindowsFailure(index, burstId) {
  const ts = new Date(Date.now() - (testBurstCount - index - 1) * 250);
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
  logon_type,
  auth_method,
  message
FROM security.auth_events
ORDER BY ts DESC
LIMIT ${limit}
FORMAT JSONEachRow
`);
  jsonResponse(res, 200, { events: rows });
}

async function handleHealth(_req, res) {
  const [natsConnected, clickhouseHealth] = await Promise.all([
    checkNats(),
    queryClickHouse(`
SELECT
  if(count() = 0, '', formatDateTime(max(ts), '%Y-%m-%d %H:%i:%S', 'UTC')) AS last_event_ts,
  countIf(ts > now() - INTERVAL 1 MINUTE) AS ingest_rate
FROM security.auth_events
FORMAT JSONEachRow
`)
      .then((rows) => ({ ok: true, row: rows[0] || {} }))
      .catch((err) => ({ ok: false, error: err.message, row: {} })),
  ]);

  const lastEventTs = clickhouseHealth.row.last_event_ts || "";
  jsonResponse(res, 200, {
    ok: natsConnected && clickhouseHealth.ok,
    nats_connected: natsConnected,
    clickhouse_connected: clickhouseHealth.ok,
    last_event_ts: lastEventTs,
    ingest_rate: Number(clickhouseHealth.row.ingest_rate || 0),
    collector_status: lastEventTs ? "connected" : "unknown",
    error: clickhouseHealth.error || "",
  });
}

async function handleGenerateTestEvent(_req, res) {
  const burstId = `demo-${Date.now()}`;
  const events = Array.from({ length: testBurstCount }, (_, index) => buildSyntheticWindowsFailure(index, burstId));

  for (const event of events) {
    await publishNats(natsSubject, event);
  }

  jsonResponse(res, 202, {
    ok: true,
    subject: natsSubject,
    events_published: events.length,
    message: "Synthetic Windows failed-login burst sent",
    sample: events[events.length - 1],
  });
}

const server = http.createServer(async (req, res) => {
  try {
    if (req.method === "OPTIONS") {
      return jsonResponse(res, 204, {});
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
    if (req.method === "POST" && path === "/generate-test-event") {
      return await handleGenerateTestEvent(req, res);
    }

    jsonResponse(res, 404, { error: "not found" });
  } catch (err) {
    console.error(`[api] ${err.message}`);
    jsonResponse(res, 500, { error: err.message });
  }
});

server.listen(listenPort, "0.0.0.0", () => {
  console.log(`[api] listening on :${listenPort}, clickhouse=${clickhouseUrl}, nats=${natsUrl}, subject=${natsSubject}`);
});
