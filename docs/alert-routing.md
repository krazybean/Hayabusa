# Alert Routing MVP

## Current flow

1. Grafana-managed alert rules evaluate and fire.
2. Notification policy routes alerts to contact-point fan-out groups.
3. Contact points post to `alert-sink` (`http://alert-sink:8080/alerts/...`) by route path.
4. `alert-sink` logs payloads locally and forwards to route-specific external webhooks when configured.

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

## Route map

- `hayabusa-platform-fanout`:
  - `/alerts/default`
  - `/alerts/email`
- `hayabusa-detection-fanout`:
  - `/alerts/detection`
  - `/alerts/chat`
- `hayabusa-oncall-webhook`:
  - `/alerts/oncall`

Policy behavior:

- High/critical alerts route to on-call endpoint.
- Detection alerts route to detection/chat fan-out.
- All other alerts route to platform/default fan-out (default + email lane).

## External forwarding (optional)

Configure using environment variables (recommended in local `.env`, which is gitignored):

```bash
HAYABUSA_EXTERNAL_WEBHOOK_URL=https://example-alert-endpoint.local/webhook
HAYABUSA_EXTERNAL_WEBHOOK_TOKEN=replace_me
# Optional alternative to token env:
# HAYABUSA_EXTERNAL_WEBHOOK_TOKEN_FILE=/run/secrets/hayabusa_external_webhook_token

# Optional route-specific URL overrides:
HAYABUSA_EXTERNAL_WEBHOOK_DEFAULT_URL=https://example.local/platform-default
HAYABUSA_EXTERNAL_WEBHOOK_DETECTION_URL=https://example.local/detection
HAYABUSA_EXTERNAL_WEBHOOK_CHAT_URL=https://example.local/chat
HAYABUSA_EXTERNAL_WEBHOOK_ONCALL_URL=https://example.local/oncall
HAYABUSA_EXTERNAL_WEBHOOK_EMAIL_URL=https://example.local/email

# Optional route-specific token / token file:
# HAYABUSA_EXTERNAL_WEBHOOK_CHAT_TOKEN=replace_me
# HAYABUSA_EXTERNAL_WEBHOOK_ONCALL_TOKEN_FILE=/run/secrets/oncall_token
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
- Router response includes `external_route` and `external_attempts` so delivery behavior is observable.

## Secret handling guidance

- Do not commit real webhook tokens in repository YAML.
- Prefer `.env` for local-only values or mount token files (`*_TOKEN_FILE`) for global/route-specific destinations.
- Keep production secrets in secret stores outside git and inject at runtime.
