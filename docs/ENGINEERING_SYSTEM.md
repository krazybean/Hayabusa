# ENGINEERING_SYSTEM.md

## System Model

Hayabusa is a pipeline:

Collector → Transport → Ingest → Store → Detect → Alert

Each stage is independent and replaceable.

---

## Directory Responsibilities

configs/
- system configuration
- detection SQL
- service configs

services/
- runtime components
- ingest logic
- detection execution

scripts/
- dev + operator tooling
- validation helpers
- bootstrap logic

docs/
- contracts
- architecture
- system rules

---

## Core Rules

### 1. Separation of Concerns

- ingest = normalization
- store = persistence
- detect = query execution
- alert = output

No cross-layer logic.

---

### 2. Data Rules

- raw events are immutable
- normalization is additive
- schema is versioned

---

### 3. Detection Rules

- SQL-driven
- config-based
- no embedded service logic

Future:
- metadata
- test harness
- orchestration

---

### 4. Observability

All components should:
- expose health where possible
- emit meaningful logs
- allow verification via queries

---

### 5. Change Model

System is currently:
- flexible
- evolving

But:
- schema changes should be cautious
- pipeline integrity must remain intact

---

## Orchestration Direction (Future)

Current:
- implicit orchestration via scripts + schedules

Future:
- centralized orchestration (Temporal or similar)
- unified control over:
  - ingestion
  - detection runs
  - alerting flows

---

## Extensibility Model

Design for replacement:

- collectors can change
- transport can change
- ingest can change
- detection engine can evolve

No component should require rewriting others.

---

## Anti-Patterns

Avoid:

- embedding detection logic in services
- coupling UI to detection logic
- hiding logic in scripts
- breaking demo flow

---

## Development Workflow

1. bring stack up
2. make small change
3. validate pipeline
4. confirm detection still works
5. iterate

---

## Guiding Principle

Prefer:

working + observable + replaceable

over:

perfect + abstract + rigid