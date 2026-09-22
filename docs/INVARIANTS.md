# Engineering Invariants

These are constraints on Hayabusa's design, not implementation suggestions. Changes that violate an invariant require an explicit architecture decision record (ADR).

1. **Raw normalized events are immutable.** Corrections and enrichment are additive; detections do not rewrite source telemetry.
2. **Collectors do not contain detection logic.** Collectors acquire and normalize telemetry only.
3. **Transport is not a source of business logic.** NATS moves durable event envelopes; rule semantics live above transport.
4. **Ingest validates before persistence.** Structurally invalid or unsupported event envelopes are rejected and must not poison retry loops.
5. **The canonical event schema is versioned.** Consumers must reject unsupported schema versions rather than silently guessing.
6. **Detection logic is declarative.** SQL defines detection queries and metadata/configuration defines thresholds and operator context. Runtime code owns execution semantics only.
7. **Detection output is reproducible.** The same event set, rule version, thresholds, and window must produce the same candidate identity.
8. **Management surfaces are local by default.** Data/control-plane ports bind to loopback unless a user explicitly opts into network exposure.
9. **Security-sensitive failures fail visibly.** Dependency failures, invalid configuration, and unsupported inputs must be observable and must not be silently treated as success.
10. **The MVP path remains continuously testable.** Collector/demo input -> transport -> ingest -> store -> detect -> alert must stay covered by automated validation.
11. **Components remain replaceable at documented boundaries.** A collector, transport, storage engine, detector runtime, or UI may evolve without requiring unrelated layers to absorb its logic.
12. **Documentation describes current behavior.** Future direction is labeled as future direction and may not contradict the running stack.
