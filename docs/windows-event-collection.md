# Windows Event Collection

This document defines the Windows collection path for the current Hayabusa MVP.

## Target Flow

```text
Windows Event Log (Application/System/Security)
-> Fluent Bit (winevtlog input)
-> Vector Windows forward lane (tcp/24225)
-> NATS JetStream
-> ClickHouse security.events
```

## Config Template

- Windows collector template: `configs/fluent-bit/windows/fluent-bit-windows.conf`
- Windows collector mTLS template: `configs/fluent-bit/windows/fluent-bit-windows-mtls.conf`
- Windows endpoint enrollment script: `scripts/enroll-windows-endpoint.sh`
- Replace `HAYABUSA_VECTOR_HOST` with the reachable IP or hostname for the Hayabusa Vector service.
- Windows endpoint validation script: `scripts/windows-endpoint-check.sh`
- mTLS cert generation script: `scripts/generate-windows-forward-certs.sh`

## Field Expectations in Hayabusa

Vector normalization writes:
- `ingest_source = vector-windows-endpoint` for tag `windows.events`
- `message` from source `message`, `log`, `msg`, or `Message`
- source details into `fields` map (including Windows keys when present)

## Deployment Notes

1. Install Fluent Bit on the Windows endpoint.
2. Build an endpoint bundle on Hayabusa host:
   - `./scripts/enroll-windows-endpoint.sh --endpoint-id WIN-ENDPOINT-01 --vector-host <hayabusa-host-ip>`
3. Copy the bundle outputs to endpoint:
   - `dist/windows-endpoints/WIN-ENDPOINT-01/fluent-bit.conf`
   - `dist/windows-endpoints/WIN-ENDPOINT-01/certs/*`
4. Start Fluent Bit as a Windows service.
5. Validate in Hayabusa:
   - `docker compose logs -f vector`
   - `./scripts/windows-endpoint-check.sh`

## Local Simulation Path

For local validation before onboarding a real endpoint:

1. `./scripts/generate-windows-events.sh`
2. `./scripts/windows-endpoint-check.sh`

This exercises the dedicated Windows lane (`24225`) using the local Fluent Bit collector.

## mTLS Hardening (Real Endpoint)

1. Vector Windows lane mTLS is enabled by default in `configs/vector/vector.yaml`.
2. Fluent Bit Windows lane mTLS output is enabled in local collector config.
3. Generate/refresh cert authority and server certs if needed:
   - `./scripts/generate-windows-forward-certs.sh`
4. Enroll endpoint with endpoint-specific client cert:
   - `./scripts/enroll-windows-endpoint.sh --endpoint-id WIN-ENDPOINT-01 --vector-host <hayabusa-host-ip>`
5. Tighten `permit_origin` in Vector to explicit endpoint CIDRs.
6. Validate:
   - `./scripts/windows-endpoint-check.sh`

## Current Scope

- Baseline strategy and config template: complete
- Dedicated Windows ingress lane in Vector (`24225`) with source tagging: complete
- Local simulator and validation script: complete
- mTLS hardening toolkit (cert script + templates): complete
- mTLS enabled in active stack path: complete
- Endpoint enrollment/identity strategy (bundle + endpoint client cert): complete
- Production hardening still pending:
  - policy rollout/update mechanism
