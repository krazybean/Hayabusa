# API_DIRECTION.md

## Status

API layer is not yet implemented.

This document defines intended direction.

---

## Goal

Expose Hayabusa as an API-first system:

- events
- detections
- alerts
- system state

---

## Planned Domains

/events
/detections
/alerts
/system

---

## Current Mapping

Today:
- ClickHouse = data layer
- scripts = control layer
- Grafana = visualization

Future:
- API replaces direct access patterns

---

## Rules

- API must not bypass pipeline logic
- API must reflect system state, not invent it
- API should sit above detection/storage layers

---

## Warning

Do NOT prematurely build API abstractions.

System must stabilize first.