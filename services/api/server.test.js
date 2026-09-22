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
