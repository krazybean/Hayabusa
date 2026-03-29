# Alert Routing MVP

## Current flow

1. Grafana-managed alert rules evaluate and fire.
2. Notification policy routes alerts to webhook contact points.
3. Contact points post to `alert-sink` (`http://alert-sink:8080/alerts/...`).
4. `alert-sink` logs payloads locally and can optionally forward to an external webhook.

## Local observability

Watch incoming webhook payloads:

```bash
docker compose logs -f alert-sink
```

Current provisioned alert classes:

- Ingestion health: `Hayabusa Ingest Stalled`
- Storage budget: `Hayabusa Events Storage Near Budget`
- Detection baseline: `Hayabusa Security Failed Login Burst`
- Detection correlations:
  - `Hayabusa Windows Failed Logon Followed by Lockout`
  - `Hayabusa Windows Failed Logon Followed by Service Install`
  - `Hayabusa Windows Failed Logon Followed by Group Change`
  - `Hayabusa Windows Lockout Followed by Service Install`

## External forwarding (optional)

Configure using environment variables (recommended in local `.env`, which is gitignored):

```bash
HAYABUSA_EXTERNAL_WEBHOOK_URL=https://example-alert-endpoint.local/webhook
HAYABUSA_EXTERNAL_WEBHOOK_TOKEN=replace_me
# Optional alternative to token env:
# HAYABUSA_EXTERNAL_WEBHOOK_TOKEN_FILE=/run/secrets/hayabusa_external_webhook_token
```

Optional behavior:

```bash
# Default false. When true, alert-sink returns non-200 if external forward fails.
HAYABUSA_ALERT_ROUTER_FAIL_ON_FORWARD_ERROR=true

# External forward timeout and retries (defaults shown):
HAYABUSA_ALERT_ROUTER_FORWARD_TIMEOUT_MS=5000
HAYABUSA_ALERT_ROUTER_FORWARD_RETRY_MAX_ATTEMPTS=3
HAYABUSA_ALERT_ROUTER_FORWARD_RETRY_BASE_MS=500
HAYABUSA_ALERT_ROUTER_FORWARD_RETRY_MAX_MS=5000
```

Then restart:

```bash
docker compose up -d alert-sink grafana
```

## Retry behavior

- External forwarding retries on timeout/network failure and HTTP `429`/`5xx`.
- HTTP `4xx` (except `429`) is treated as non-retryable.
- Retry delay uses exponential backoff from `HAYABUSA_ALERT_ROUTER_FORWARD_RETRY_BASE_MS`, capped by `HAYABUSA_ALERT_ROUTER_FORWARD_RETRY_MAX_MS`.
- Router response includes `external_attempts` so delivery behavior is observable.

## Secret handling guidance

- Do not commit real webhook tokens in repository YAML.
- Prefer `.env` for local-only values or mount a token file and set `HAYABUSA_EXTERNAL_WEBHOOK_TOKEN_FILE`.
- Keep production secrets in secret stores outside git and inject at runtime.
