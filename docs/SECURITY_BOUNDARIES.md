# Security Boundaries

Hayabusa is currently a local-first, single-host security platform MVP. Its safe operating assumption is a trusted host and trusted collector network.

## Default exposure

Docker Compose binds management and data-plane surfaces to loopback by default:

- Hayabusa API: 127.0.0.1:8080
- Web UI: 127.0.0.1:3000
- Grafana: 127.0.0.1:3001
- ClickHouse HTTP/native: 127.0.0.1:8123 / 9000
- NATS monitoring: 127.0.0.1:8222
- Vector health: 127.0.0.1:8686
- Alert sink: 127.0.0.1:5678

Collector ingress is also loopback-only by default:

- NATS collector ingress: 127.0.0.1:4222
- Syslog TCP/UDP: 127.0.0.1:1514
- Legacy Windows forward lane: 127.0.0.1:24225

Remote collection is an explicit opt-in. Copy `.env.example` to `.env` and set the relevant `HAYABUSA_*_BIND` variable to the specific trusted LAN interface/IP that collectors must reach. Avoid wildcard binds such as `0.0.0.0` unless the network boundary has been deliberately reviewed.

## Current trust assumptions

- collector ingress stays on loopback unless the operator explicitly binds it to a trusted local/LAN interface
- the API has no authentication or RBAC
- NATS collector ingress has no supported credentials/TLS onboarding path yet
- ClickHouse and management surfaces are not intended for remote exposure
- `POST /generate-test-event` is disabled by default in the API process and is enabled explicitly by the local demo Compose stack

## Before remote or multi-user operation

The following become required rather than optional hardening:

1. authenticate and authorize API callers
2. configure NATS credentials and TLS for collector ingress
3. define certificate/key rotation and secret storage
4. separate demo mutation endpoints from production control-plane routes
5. define audit logging for security-sensitive actions
6. review reverse-proxy/TLS termination and trusted network boundaries

Until those requirements are implemented, Hayabusa should not be presented as internet-facing or multi-user secure.
