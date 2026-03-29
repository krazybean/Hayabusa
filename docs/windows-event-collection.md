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
2. Copy the template config and set `Host` to your Hayabusa host.
3. Start Fluent Bit as a Windows service.
4. Validate in Hayabusa:
   - `docker compose logs -f vector`
   - `./scripts/windows-endpoint-check.sh`

## Local Simulation Path

For local validation before onboarding a real endpoint:

1. `./scripts/generate-windows-events.sh`
2. `./scripts/windows-endpoint-check.sh`

This exercises the dedicated Windows lane (`24225`) using the local Fluent Bit collector.

## mTLS Hardening (Real Endpoint)

1. Generate certs locally:
   - `./scripts/generate-windows-forward-certs.sh`
2. Merge TLS settings from:
   - `configs/vector/windows-forward-mtls-example.yaml`
   into `sources.ingest_fluent_windows_forward` in `configs/vector/vector.yaml`
3. Restart Vector:
   - `DOCKER_CONFIG=/tmp/docker-nocreds docker compose up -d vector`
4. On Windows endpoint, use:
   - `configs/fluent-bit/windows/fluent-bit-windows-mtls.conf`
5. Copy certs to endpoint:
   - `ca.crt`, `client.crt`, `client.key`
6. Tighten `permit_origin` in Vector to explicit endpoint CIDRs.
7. Validate:
   - `./scripts/windows-endpoint-check.sh`

## Current Scope

- Baseline strategy and config template: complete
- Dedicated Windows ingress lane in Vector (`24225`) with source tagging: complete
- Local simulator and validation script: complete
- mTLS hardening toolkit (cert script + templates): complete
- Production hardening still pending:
  - endpoint enrollment/identity strategy
  - policy rollout/update mechanism
