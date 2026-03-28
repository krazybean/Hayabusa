# Windows Event Collection (Baseline)

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
- Replace `HAYABUSA_VECTOR_HOST` with the reachable IP or hostname for the Hayabusa Vector service.
- Windows endpoint validation script: `scripts/windows-endpoint-check.sh`

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

## Current Scope

- Baseline strategy and config template: complete
- Dedicated Windows ingress lane in Vector (`24225`) with source tagging: complete
- Production hardening pending:
  - TLS and authentication on forward path (template placeholders included)
  - endpoint enrollment/identity strategy
  - policy rollout/update mechanism
