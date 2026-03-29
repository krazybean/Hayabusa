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
- Windows real-host cutover guard script: `scripts/windows-real-host-cutover-check.sh`
- Windows permit-origin helper script: `scripts/set-windows-permit-origin.sh`
- Windows one-command cutover orchestrator: `scripts/windows-cutover-orchestrator.sh`
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
   - `WINDOWS_CHECK_COMPUTER=WIN-ENDPOINT-01 ./scripts/windows-endpoint-check.sh`

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

## Real-Host Cutover Checklist

Preferred one-command path:

```bash
./scripts/windows-cutover-orchestrator.sh \
  --endpoint-id WIN-ENDPOINT-01 \
  --vector-host 192.168.1.50 \
  --expected-cidr 192.168.10.22/32 \
  --computer WIN-ENDPOINT-01
```

This runs:
- enrollment bundle generation
- `permit_origin` update
- Vector restart
- endpoint + CIDR hardening validation

Use `--dry-run` first to preview all steps without changing files/services.

Manual path:

1. Enroll endpoint bundle:
   - `./scripts/enroll-windows-endpoint.sh --endpoint-id WIN-ENDPOINT-01 --vector-host <hayabusa-host-ip>`
2. Update `configs/vector/vector.yaml` `permit_origin` to endpoint CIDR(s), typically `/32` per host.
   - Helper: `./scripts/set-windows-permit-origin.sh --cidr 192.168.10.22/32`
3. Remove broad CIDRs (`10.0.0.0/8`, `172.16.0.0/12`, `192.168.0.0/16`) for production-like cutover.
4. Restart Vector:
   - `DOCKER_CONFIG=/tmp/docker-nocreds docker compose up -d vector`
5. Validate endpoint-specific traffic and CIDR hardening:
   - `./scripts/windows-real-host-cutover-check.sh --computer WIN-ENDPOINT-01 --expected-cidr 192.168.10.22/32`

## Current Scope

- Baseline strategy and config template: complete
- Dedicated Windows ingress lane in Vector (`24225`) with source tagging: complete
- Local simulator and validation script: complete
- mTLS hardening toolkit (cert script + templates): complete
- mTLS enabled in active stack path: complete
- Endpoint enrollment/identity strategy (bundle + endpoint client cert): complete
- Production hardening still pending:
  - policy rollout/update mechanism
