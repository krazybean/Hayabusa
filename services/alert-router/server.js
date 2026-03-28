const fs = require("fs");
const http = require("http");

const listenPort = Number(process.env.ALERT_ROUTER_LISTEN_PORT || 8080);
const externalWebhookUrl = (process.env.ALERT_ROUTER_EXTERNAL_WEBHOOK_URL || "").trim();
const externalTokenEnv = (process.env.ALERT_ROUTER_EXTERNAL_WEBHOOK_TOKEN || "").trim();
const externalTokenFile = (process.env.ALERT_ROUTER_EXTERNAL_WEBHOOK_TOKEN_FILE || "").trim();
const failOnForwardError = String(process.env.ALERT_ROUTER_FAIL_ON_FORWARD_ERROR || "false").toLowerCase() === "true";

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

async function forwardToExternal(payload, contentType, sourcePath) {
  if (!externalWebhookUrl) {
    log(`forward-skipped path=${sourcePath} reason=no-external-webhook-configured`);
    return { forwarded: false, ok: true, status: 0 };
  }

  const token = resolveToken();
  const headers = {
    "content-type": contentType || "application/json",
  };
  if (token) {
    headers.authorization = `Bearer ${token}`;
  }

  try {
    const resp = await fetch(externalWebhookUrl, {
      method: "POST",
      headers,
      body: payload,
    });

    log(`forward-result path=${sourcePath} status=${resp.status} ok=${resp.ok}`);
    return { forwarded: true, ok: resp.ok, status: resp.status };
  } catch (err) {
    log(`forward-error path=${sourcePath} err="${err.message}"`);
    return { forwarded: true, ok: false, status: 0 };
  }
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
    let forwardResult = { forwarded: false, ok: true, status: 0 };
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
    `listening=0.0.0.0:${listenPort} external_webhook_url=${externalWebhookUrl || "<disabled>"} token_source=${tokenMode} fail_on_forward_error=${failOnForwardError}`,
  );
});
