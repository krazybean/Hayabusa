# Endpoint Policy + Drift Model (MVP)

Hayabusa uses a YAML policy file as the source of truth for expected Windows endpoints.

Policy file:
- `configs/endpoints/windows-endpoints.yaml`

Drift check command:
- `./scripts/endpoint-policy-drift-check.sh`

## Policy Structure

```yaml
defaults:
  lane: vector-windows-endpoint
  max_stale_minutes: 120
  required: false

endpoints:
  - id: WIN-ENDPOINT-01
    computer: WIN-ENDPOINT-01
    required: true
    max_stale_minutes: 120
```

Field notes:
- `id`: policy identifier (human-managed)
- `computer`: expected endpoint identity as it appears in telemetry (`fields['computer']`)
- `lane`: expected ingest lane (default: `vector-windows-endpoint`)
- `max_stale_minutes`: endpoint freshness threshold
- `required`: when `true`, missing/stale endpoint state fails drift check

## Drift Semantics

Required endpoints (`required: true`):
- Missing in telemetry: drift
- Present on wrong lane: drift
- Present but stale beyond threshold: drift

Optional endpoints (`required: false`):
- Missing/stale reported as warning
- Does not fail command

## Commands

Run full policy check:

```bash
./scripts/endpoint-policy-drift-check.sh
```

Check one endpoint:

```bash
./scripts/endpoint-policy-drift-check.sh --only-id WIN-ENDPOINT-01
```

Lab mode (report drift, but do not fail):

```bash
./scripts/endpoint-policy-drift-check.sh --soft-fail
```

## Operational Recommendation

After first successful real-host cutover:
1. Set endpoint `required: true`
2. Tune `max_stale_minutes` to your expected heartbeat/log cadence
3. Run drift check before/after maintenance windows
