const fs = require("fs");
const http = require("http");

const listenPort = Number(process.env.ALERT_ROUTER_LISTEN_PORT || 8080);
const externalWebhookUrl = readEnv("ALERT_ROUTER_EXTERNAL_WEBHOOK_URL");
const externalTokenEnv = readEnv("ALERT_ROUTER_EXTERNAL_WEBHOOK_TOKEN");
const externalTokenFile = readEnv("ALERT_ROUTER_EXTERNAL_WEBHOOK_TOKEN_FILE");
const failOnForwardError = String(process.env.ALERT_ROUTER_FAIL_ON_FORWARD_ERROR || "false").toLowerCase() === "true";
const forwardTimeoutMs = parseIntegerEnv("ALERT_ROUTER_FORWARD_TIMEOUT_MS", 5000, 100);
const forwardRetryMaxAttempts = parseIntegerEnv("ALERT_ROUTER_FORWARD_RETRY_MAX_ATTEMPTS", 3, 1);
const forwardRetryBaseMs = parseIntegerEnv("ALERT_ROUTER_FORWARD_RETRY_BASE_MS", 500, 0);
const forwardRetryMaxMs = parseIntegerEnv("ALERT_ROUTER_FORWARD_RETRY_MAX_MS", 5000, 0);
const routeKeys = ["default", "detection", "chat", "oncall", "email"];
const routeConfigByKey = buildRouteConfigByKey();

function readEnv(name) {
  return (process.env[name] || "").trim();
}

function parseIntegerEnv(name, defaultValue, minValue) {
  const raw = readEnv(name);
  if (!raw) return defaultValue;
  const parsed = Number(raw);
  if (!Number.isFinite(parsed) || parsed < minValue) {
    return defaultValue;
  }
  return Math.floor(parsed);
}

function buildRouteConfigByKey() {
  const config = {};
  for (const routeKey of routeKeys) {
    const upper = routeKey.toUpperCase();
    config[routeKey] = {
      routeKey,
      url: readEnv(`ALERT_ROUTER_EXTERNAL_WEBHOOK_${upper}_URL`),
      tokenEnv: readEnv(`ALERT_ROUTER_EXTERNAL_WEBHOOK_${upper}_TOKEN`),
      tokenFile: readEnv(`ALERT_ROUTER_EXTERNAL_WEBHOOK_${upper}_TOKEN_FILE`),
    };
  }
  return config;
}

function readTokenFromFile(path, context) {
  if (!path) return "";
  try {
    return fs.readFileSync(path, "utf8").trim();
  } catch (err) {
    log(`token-file-read-failed context=${context} path=${path} err="${err.message}"`);
    return "";
  }
}

function routeKeyFromPath(path) {
  const segments = path.split("/").filter(Boolean);
  if (segments.length >= 2 && segments[0] === "alerts") {
    const candidate = segments[1].toLowerCase();
    if (Object.prototype.hasOwnProperty.call(routeConfigByKey, candidate)) {
      return candidate;
    }
  }
  return "default";
}

function resolveForwardTarget(path) {
  const routeKey = routeKeyFromPath(path);
  const routeConfig = routeConfigByKey[routeKey] || {
    routeKey,
    url: "",
    tokenEnv: "",
    tokenFile: "",
  };

  const url = routeConfig.url || externalWebhookUrl;
  let token = "";
  let tokenSource = "none";

  if (routeConfig.tokenEnv) {
    token = routeConfig.tokenEnv;
    tokenSource = `${routeKey}:env`;
  } else if (routeConfig.tokenFile) {
    token = readTokenFromFile(routeConfig.tokenFile, `${routeKey}:file`);
    if (token) {
      tokenSource = `${routeKey}:file`;
    }
  }

  if (!token && externalTokenEnv) {
    token = externalTokenEnv;
    tokenSource = "global:env";
  } else if (!token && externalTokenFile) {
    token = readTokenFromFile(externalTokenFile, "global:file");
    if (token) {
      tokenSource = "global:file";
    }
  }

  return {
    routeKey,
    url,
    token,
    tokenSource,
  };
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

async function forwardAttempt(targetUrl, routeKey, payload, contentType, sourcePath, headers, attempt) {
  const controller = new AbortController();
  const timeout = setTimeout(() => controller.abort(), forwardTimeoutMs);

  try {
    const resp = await fetch(targetUrl, {
      method: "POST",
      headers,
      body: payload,
      signal: controller.signal,
    });
    const retryable = shouldRetryStatus(resp.status);
    log(
      `forward-attempt route=${routeKey} path=${sourcePath} attempt=${attempt}/${forwardRetryMaxAttempts} status=${resp.status} ok=${resp.ok} retryable=${retryable}`,
    );
    return { ok: resp.ok, status: resp.status, retryable };
  } catch (err) {
    const isTimeout = err && err.name === "AbortError";
    log(
      `forward-attempt-error route=${routeKey} path=${sourcePath} attempt=${attempt}/${forwardRetryMaxAttempts} timeout=${isTimeout} err="${err.message}"`,
    );
    return { ok: false, status: 0, retryable: true };
  } finally {
    clearTimeout(timeout);
  }
}

async function forwardToExternal(payload, contentType, sourcePath) {
  const target = resolveForwardTarget(sourcePath);
  if (!target.url) {
    log(`forward-skipped route=${target.routeKey} path=${sourcePath} reason=no-external-webhook-configured`);
    return { forwarded: false, ok: true, status: 0, attempts: 0, route: target.routeKey };
  }

  const headers = {
    "content-type": contentType || "application/json",
  };
  if (target.token) {
    headers.authorization = `Bearer ${target.token}`;
  }

  log(
    `forward-start route=${target.routeKey} path=${sourcePath} token_source=${target.tokenSource} retry_max_attempts=${forwardRetryMaxAttempts}`,
  );

  let lastStatus = 0;
  for (let attempt = 1; attempt <= forwardRetryMaxAttempts; attempt += 1) {
    const result = await forwardAttempt(target.url, target.routeKey, payload, contentType, sourcePath, headers, attempt);
    lastStatus = result.status;

    if (result.ok) {
      return { forwarded: true, ok: true, status: result.status, attempts: attempt, route: target.routeKey };
    }

    if (!result.retryable || attempt >= forwardRetryMaxAttempts) {
      break;
    }

    const delayMs = backoffDelayMs(attempt);
    log(
      `forward-retry-scheduled route=${target.routeKey} path=${sourcePath} next_attempt=${attempt + 1} delay_ms=${delayMs}`,
    );
    await sleep(delayMs);
  }

  return {
    forwarded: true,
    ok: false,
    status: lastStatus,
    attempts: forwardRetryMaxAttempts,
    route: target.routeKey,
  };
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
    let forwardResult = { forwarded: false, ok: true, status: 0, attempts: 0, route: "none" };
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
        external_route: forwardResult.route,
        external_status: forwardResult.status,
        external_attempts: forwardResult.attempts,
      }),
    );
  });
});

server.listen(listenPort, "0.0.0.0", () => {
  const tokenMode = externalTokenEnv ? "global:env" : externalTokenFile ? `global:file:${externalTokenFile}` : "none";
  const routeModes = routeKeys
    .map((routeKey) => {
      const routeCfg = routeConfigByKey[routeKey];
      if (routeCfg.url) return `${routeKey}=route-url`;
      if (externalWebhookUrl) return `${routeKey}=global-fallback`;
      return `${routeKey}=disabled`;
    })
    .join(",");
  log(
    `listening=0.0.0.0:${listenPort} external_webhook_url=${externalWebhookUrl || "<disabled>"} token_source=${tokenMode} route_modes=${routeModes} fail_on_forward_error=${failOnForwardError} forward_timeout_ms=${forwardTimeoutMs} retry_max_attempts=${forwardRetryMaxAttempts} retry_base_ms=${forwardRetryBaseMs} retry_max_ms=${forwardRetryMaxMs}`,
  );
});
