# Alert Routing MVP

## Current flow

1. Grafana evaluates `Hayabusa Security Failed Login Burst`.
2. When the rule is firing, Grafana posts to `http://alert-sink:8080/alerts/default`.
3. `alert-sink` logs the payload.
4. If `HAYABUSA_EXTERNAL_WEBHOOK_URL` is set, `alert-sink` forwards the same payload outward.

## Active alert

- Rule title: `Hayabusa Security Failed Login Burst`
- Query source: `security.alert_candidates`
- Contact point: `hayabusa-webhook`
- Endpoint: `/alerts/default`

## External forwarding (optional)

Configure with:

```bash
HAYABUSA_EXTERNAL_WEBHOOK_URL=https://example-alert-endpoint.local/webhook
HAYABUSA_EXTERNAL_WEBHOOK_TOKEN=replace_me
# HAYABUSA_EXTERNAL_WEBHOOK_TOKEN_FILE=/run/secrets/hayabusa_external_webhook_token
```

Optional retry settings:

```bash
HAYABUSA_ALERT_ROUTER_FAIL_ON_FORWARD_ERROR=true
HAYABUSA_ALERT_ROUTER_FORWARD_TIMEOUT_MS=5000
HAYABUSA_ALERT_ROUTER_FORWARD_RETRY_MAX_ATTEMPTS=3
HAYABUSA_ALERT_ROUTER_FORWARD_RETRY_BASE_MS=500
HAYABUSA_ALERT_ROUTER_FORWARD_RETRY_MAX_MS=5000
```

Then restart:

```bash
docker compose up -d alert-sink grafana
```

## Verify

```bash
docker compose logs -f alert-sink
```

You should see `received method=POST path=/alerts/default` when the Grafana rule fires.
