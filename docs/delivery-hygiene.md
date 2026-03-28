# Delivery Hygiene Policy

## Purpose

Keep delivery traceable and restart-friendly for every feature.

## Source of Truth

Use these artifacts together on each feature:

1. Linear issue (planning + ownership + state)
2. `STATUS.md` (current platform snapshot and next priorities)
3. `docs/component-checklist.md` (component-level progress)
4. Relevant runbooks/docs (`README.md`, `docs/*`)

## Required Feature Lifecycle

1. Start
- Confirm a Linear issue exists and is scoped.
- Move issue to `In Progress`.
- Add acceptance criteria to issue description.

2. Build
- Keep changes modular and aligned to architecture boundaries.
- Validate locally with smoke tests and targeted checks.

3. Wrap up
- Move issue to `In Review` when implementation and verification are complete.
- Update `STATUS.md` with outcome and next dependency.
- Update `docs/component-checklist.md` for completed items.
- Update user-facing docs for any new command, endpoint, or alert.

4. Close
- Move issue to `Done` after review/acceptance.
- Add a short closeout note in Linear: what changed, how verified, residual risk.

## Definition of Done (Feature)

- Acceptance criteria met
- Relevant tests/checks pass
- Operational docs updated
- Status artifacts updated (`STATUS.md`, checklist)
- Linear issue moved to the correct end state

## New Session Bootstrap

Use this sequence at the start of a fresh window:

1. Open `STATUS.md`
2. Run `./scripts/smoke-test.sh`
3. Run `./scripts/storage-budget-guard.sh`
4. Review `docs/component-checklist.md` + `docs/wazuh-parity-map.md`
5. Continue from the top unfinished item in `STATUS.md` priority queue
