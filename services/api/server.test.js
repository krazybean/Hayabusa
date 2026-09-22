const test = require("node:test");
const assert = require("node:assert/strict");

const {
  formatEventTimestamp,
  limitFromUrl,
  parseAllowedOrigins,
  parseLimit,
} = require("./lib/core");
const { buildSyntheticWindowsFailure } = require("./lib/demo");
const { parseNatsEndpoint } = require("./lib/nats");
const { createServer, loadRuntimeConfig } = require("./server");

test("parseLimit clamps invalid and oversized limits", () => {
  assert.equal(parseLimit("25", 50), 25);
  assert.equal(parseLimit("0", 50), 50);
  assert.equal(parseLimit("nope", 50), 50);
  assert.equal(parseLimit("999", 50), 200);
});

test("parseNatsEndpoint accepts only valid NATS URLs", () => {
  assert.deepEqual(parseNatsEndpoint("nats://example.test:4333"), {
    host: "example.test",
    port: 4333,
  });
  assert.deepEqual(parseNatsEndpoint("nats://example.test"), {
    host: "example.test",
    port: 4222,
  });
  assert.throws(() => parseNatsEndpoint("https://example.test"), /Unsupported NATS_URL protocol/);
  assert.throws(() => parseNatsEndpoint("nats://example.test:70000"), /Invalid URL|Invalid NATS_URL port/);
});

test("formatEventTimestamp emits UTC millisecond precision", () => {
  const value = new Date("2026-09-21T12:34:56.789Z");
  assert.equal(formatEventTimestamp(value), "2026-09-21 12:34:56.789");
});

test("limitFromUrl uses bounded query limits", () => {
  assert.equal(limitFromUrl("/alerts?limit=20", 50), 20);
  assert.equal(limitFromUrl("/alerts?limit=999", 50), 200);
  assert.equal(limitFromUrl("/alerts?limit=bad", 25), 25);
});

test("parseAllowedOrigins trims and removes empty entries", () => {
  const origins = parseAllowedOrigins(" http://localhost:3000, ,http://127.0.0.1:3000 ");
  assert.equal(origins.size, 2);
  assert.equal(origins.has("http://localhost:3000"), true);
  assert.equal(origins.has("http://127.0.0.1:3000"), true);
});

test("synthetic Windows events conform to the canonical envelope", () => {
  const event = buildSyntheticWindowsFailure(0, "test-burst", 5);
  assert.equal(event.platform, "windows");
  assert.equal(event.schema_version, "hayabusa.event.v1");
  assert.equal(event.ingest_source, "vector-windows-endpoint");
  assert.equal(event.fields.event_type, "login");
  assert.equal(event.fields.status, "failure");
  assert.equal(event.fields.event_id, "4625");
});

test("loadRuntimeConfig preserves safe defaults", () => {
  const config = loadRuntimeConfig({});
  assert.equal(config.listenPort, 8080);
  assert.equal(config.demoEndpointsEnabled, false);
  assert.equal(config.allowedOrigins.has("http://localhost:3000"), true);
});

async function withServer(options, fn) {
  const server = createServer(options);
  await new Promise((resolve) => server.listen(0, "127.0.0.1", resolve));
  const address = server.address();
  try {
    await fn(`http://127.0.0.1:${address.port}`);
  } finally {
    await new Promise((resolve) => server.close(resolve));
  }
}

function testConfig(overrides = {}) {
  return {
    listenPort: 0,
    clickhouseUrl: "http://unused",
    natsUrl: "nats://unused:4222",
    natsSubject: "security.events",
    defaultLimit: 50,
    testBurstCount: 3,
    demoEndpointsEnabled: false,
    allowedOrigins: new Set(["http://localhost:3000"]),
    ...overrides,
  };
}

test("health route reports dependency state without leaking backend errors", async () => {
  const clickhouse = {
    async query() {
      return [{ last_event_ts: "2026-09-21 12:00:00", ingest_rate: "7" }];
    },
  };
  const nats = { async check() { return true; }, async publish() {} };

  await withServer({ config: testConfig(), clickhouse, nats }, async (baseUrl) => {
    const resp = await fetch(`${baseUrl}/health`);
    assert.equal(resp.status, 200);
    assert.deepEqual(await resp.json(), {
      ok: true,
      nats_connected: true,
      clickhouse_connected: true,
      last_event_ts: "2026-09-21 12:00:00",
      ingest_rate: 7,
      collector_status: "connected",
      error: "",
    });
  });
});

test("events route clamps query limits", async () => {
  let sql = "";
  const clickhouse = {
    async query(value) {
      sql = value;
      return [{ user: "alice" }];
    },
  };
  const nats = { async check() { return true; }, async publish() {} };

  await withServer({ config: testConfig(), clickhouse, nats }, async (baseUrl) => {
    const resp = await fetch(`${baseUrl}/events?limit=9999`);
    assert.equal(resp.status, 200);
    assert.deepEqual(await resp.json(), { events: [{ user: "alice" }] });
    assert.match(sql, /LIMIT 200/);
  });
});

test("demo mutation route is disabled unless explicitly enabled", async () => {
  const clickhouse = { async query() { return []; } };
  const nats = { async check() { return true; }, async publish() {} };

  await withServer({ config: testConfig(), clickhouse, nats }, async (baseUrl) => {
    const resp = await fetch(`${baseUrl}/generate-test-event`, { method: "POST" });
    assert.equal(resp.status, 404);
  });
});

test("enabled demo mutation publishes the configured burst", async () => {
  const published = [];
  const clickhouse = { async query() { return []; } };
  const nats = {
    async check() { return true; },
    async publish(subject, payload) { published.push({ subject, payload }); },
  };

  await withServer({
    config: testConfig({ demoEndpointsEnabled: true, testBurstCount: 3 }),
    clickhouse,
    nats,
  }, async (baseUrl) => {
    const resp = await fetch(`${baseUrl}/generate-test-event`, { method: "POST" });
    assert.equal(resp.status, 202);
    const body = await resp.json();
    assert.equal(body.events_published, 3);
    assert.equal(published.length, 3);
    assert.equal(published.every((item) => item.subject === "security.events"), true);
  });
});

test("CORS is granted only to configured origins", async () => {
  const clickhouse = { async query() { return []; } };
  const nats = { async check() { return true; }, async publish() {} };

  await withServer({ config: testConfig(), clickhouse, nats }, async (baseUrl) => {
    const allowed = await fetch(`${baseUrl}/events`, {
      headers: { origin: "http://localhost:3000" },
    });
    assert.equal(allowed.headers.get("access-control-allow-origin"), "http://localhost:3000");

    const denied = await fetch(`${baseUrl}/events`, {
      headers: { origin: "https://untrusted.example" },
    });
    assert.equal(denied.headers.get("access-control-allow-origin"), null);
  });
});
