const fs = require("fs");
const http = require("http");

const listenPort = Number(process.env.ALERT_ROUTER_LISTEN_PORT || 8080);
const externalWebhookUrl = (process.env.ALERT_ROUTER_EXTERNAL_WEBHOOK_URL || "").trim();
const externalTokenEnv = (process.env.ALERT_ROUTER_EXTERNAL_WEBHOOK_TOKEN || "").trim();
const externalTokenFile = (process.env.ALERT_ROUTER_EXTERNAL_WEBHOOK_TOKEN_FILE || "").trim();
const failOnForwardError = String(process.env.ALERT_ROUTER_FAIL_ON_FORWARD_ERROR || "false").toLowerCase() === "true";
const forwardTimeoutMs = parseIntegerEnv("ALERT_ROUTER_FORWARD_TIMEOUT_MS", 5000, 100);
const forwardRetryMaxAttempts = parseIntegerEnv("ALERT_ROUTER_FORWARD_RETRY_MAX_ATTEMPTS", 3, 1);
const forwardRetryBaseMs = parseIntegerEnv("ALERT_ROUTER_FORWARD_RETRY_BASE_MS", 500, 0);
const forwardRetryMaxMs = parseIntegerEnv("ALERT_ROUTER_FORWARD_RETRY_MAX_MS", 5000, 0);

function parseIntegerEnv(name, defaultValue, minValue) {
  const raw = (process.env[name] || "").trim();
  if (!raw) return defaultValue;
  const parsed = Number(raw);
  if (!Number.isFinite(parsed) || parsed < minValue) {
    return defaultValue;
  }
  return Math.floor(parsed);
}

function readTokenFromFile(path) {
  if (!path) return "";
  try {
    return fs.readFileSync(path, "utf8").trim();
  } catch (err) {
    log(`token-file-read-failed path=${path} err="${err.message}"`);
    return "";
  }
}

function resolveToken() {
  if (externalTokenEnv) return externalTokenEnv;
  return readTokenFromFile(externalTokenFile);
}

function nowIso() {
  return new Date().toISOString();
}

function log(message) {
  console.log(`${nowIso()} [alert-router] ${message}`);
}

function shouldRetryStatus(status) {
  return status === 429 || status >= 500;
}

function backoffDelayMs(attempt) {
  if (forwardRetryBaseMs <= 0) return 0;
  const maxDelay = Math.max(forwardRetryBaseMs, forwardRetryMaxMs);
  return Math.min(maxDelay, forwardRetryBaseMs * 2 ** Math.max(0, attempt - 1));
}

function sleep(ms) {
  if (ms <= 0) return Promise.resolve();
  return new Promise((resolve) => setTimeout(resolve, ms));
}

async function forwardAttempt(payload, contentType, sourcePath, headers, attempt) {
  const controller = new AbortController();
  const timeout = setTimeout(() => controller.abort(), forwardTimeoutMs);

  try {
    const resp = await fetch(externalWebhookUrl, {
      method: "POST",
      headers,
      body: payload,
      signal: controller.signal,
    });
    const retryable = shouldRetryStatus(resp.status);
    log(
      `forward-attempt path=${sourcePath} attempt=${attempt}/${forwardRetryMaxAttempts} status=${resp.status} ok=${resp.ok} retryable=${retryable}`,
    );
    return { ok: resp.ok, status: resp.status, retryable };
  } catch (err) {
    const isTimeout = err && err.name === "AbortError";
    log(
      `forward-attempt-error path=${sourcePath} attempt=${attempt}/${forwardRetryMaxAttempts} timeout=${isTimeout} err="${err.message}"`,
    );
    return { ok: false, status: 0, retryable: true };
  } finally {
    clearTimeout(timeout);
  }
}

async function forwardToExternal(payload, contentType, sourcePath) {
  if (!externalWebhookUrl) {
    log(`forward-skipped path=${sourcePath} reason=no-external-webhook-configured`);
    return { forwarded: false, ok: true, status: 0, attempts: 0 };
  }

  const token = resolveToken();
  const headers = {
    "content-type": contentType || "application/json",
  };
  if (token) {
    headers.authorization = `Bearer ${token}`;
  }

  let lastStatus = 0;
  for (let attempt = 1; attempt <= forwardRetryMaxAttempts; attempt += 1) {
    const result = await forwardAttempt(payload, contentType, sourcePath, headers, attempt);
    lastStatus = result.status;

    if (result.ok) {
      return { forwarded: true, ok: true, status: result.status, attempts: attempt };
    }

    if (!result.retryable || attempt >= forwardRetryMaxAttempts) {
      break;
    }

    const delayMs = backoffDelayMs(attempt);
    log(`forward-retry-scheduled path=${sourcePath} next_attempt=${attempt + 1} delay_ms=${delayMs}`);
    await sleep(delayMs);
  }

  return { forwarded: true, ok: false, status: lastStatus, attempts: forwardRetryMaxAttempts };
}

const server = http.createServer((req, res) => {
  if (req.method === "GET" && req.url === "/health") {
    res.writeHead(200, { "content-type": "application/json" });
    res.end(JSON.stringify({ ok: true, service: "alert-router" }));
    return;
  }

  const chunks = [];
  req.on("data", (chunk) => {
    chunks.push(chunk);
  });

  req.on("end", async () => {
    const bodyBuffer = Buffer.concat(chunks);
    const bodyText = bodyBuffer.toString("utf8");
    const contentType = req.headers["content-type"] || "application/json";
    const requestPath = req.url || "/";

    log(`received method=${req.method} path=${requestPath} bytes=${bodyBuffer.length}`);
    if (bodyText) {
      log(`payload path=${requestPath} body=${bodyText}`);
    }

    const shouldForward = req.method === "POST" && requestPath.startsWith("/alerts/");
    let forwardResult = { forwarded: false, ok: true, status: 0, attempts: 0 };
    if (shouldForward) {
      forwardResult = await forwardToExternal(bodyText, contentType, requestPath);
    }

    if (failOnForwardError && forwardResult.forwarded && !forwardResult.ok) {
      res.writeHead(502, { "content-type": "application/json" });
      res.end(JSON.stringify({ ok: false, forwarded: true, reason: "external-forward-failed" }));
      return;
    }

    res.writeHead(200, { "content-type": "application/json" });
    res.end(
      JSON.stringify({
        ok: true,
        forwarded: forwardResult.forwarded,
        external_status: forwardResult.status,
        external_attempts: forwardResult.attempts,
      }),
    );
  });
});

server.listen(listenPort, "0.0.0.0", () => {
  const tokenMode = externalTokenEnv
    ? "env"
    : externalTokenFile
      ? `file:${externalTokenFile}`
      : "none";
  log(
    `listening=0.0.0.0:${listenPort} external_webhook_url=${externalWebhookUrl || "<disabled>"} token_source=${tokenMode} fail_on_forward_error=${failOnForwardError} forward_timeout_ms=${forwardTimeoutMs} retry_max_attempts=${forwardRetryMaxAttempts} retry_base_ms=${forwardRetryBaseMs} retry_max_ms=${forwardRetryMaxMs}`,
  );
});
