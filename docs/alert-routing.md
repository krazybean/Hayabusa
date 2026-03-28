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
```

Then restart:

```bash
docker compose up -d alert-sink grafana
```

## Secret handling guidance

- Do not commit real webhook tokens in repository YAML.
- Prefer `.env` for local-only values or mount a token file and set `HAYABUSA_EXTERNAL_WEBHOOK_TOKEN_FILE`.
- Keep production secrets in secret stores outside git and inject at runtime.
