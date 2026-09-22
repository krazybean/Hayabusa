# API Direction

## Status

A minimal API is implemented at `services/api/server.js`.

Current endpoints:

- `GET /health`
- `GET /events`
- `GET /alerts`
- `POST /generate-test-event`

The current API is an MVP facade for the local demo. It is **not** yet the stable public control-plane API and it has no authentication/RBAC.

## Goal

Evolve Hayabusa toward an API-first system interface for:

- events
- detections
- findings/alerts
- system state

## Current Mapping

Today:

- ClickHouse = data layer
- NATS = event transport
- detection service = rule execution
- API = minimal read/demo facade
- web = guided local UI
- Grafana = visualization and alert evaluation

Future:

- formalize API contracts before remote or multi-user operation
- put authenticated control-plane operations behind the API
- reduce direct operator dependence on ClickHouse/Grafana

## Rules

- API must not bypass pipeline logic
- API must reflect system state, not invent it
- API should sit above detection/storage layers
- remote exposure requires an explicit security model
- demo-only mutation endpoints must stay distinguishable from production control-plane operations
