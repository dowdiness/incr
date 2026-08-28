# Nodeflow kernel spike

**Reader:** maintainers evaluating a typed editable semantic graph over Incr Query.

**Decision:** keep Nodeflow opaque and closed while proving typed graph edits and atomic publication.

**Keep until:** Issue #496's finite evidence prototype reaches a documented verdict.

**Disposition:** active spike; this slice is evidence, not a production API commitment.

## Scope matrix

| Capability | Status |
|---|---|
| Opaque graph/node/port identities | Implemented |
| Closed descriptors: Number, Boolean, Add, Multiply, SafeDivide, Display, OptionalOffset | Implemented |
| Pure validation and ordinary edit rejection | Implemented |
| Atomic binding change sets and typed parameters | Implemented |
| Missing/unavailable/current demand projection | Implemented |
| Typed Formula Failure and ordered evaluation issues | Implemented |
| Display Action availability and explicit invocation | Implemented |
| GraphDocument JSON codec and atomic restoration | Implemented |
| Atomic Node removal and Region lifetime publication | Implemented |
| External persistence storage engine | Deferred |
| General cycles beyond the existing kernel catch shape | Deferred |
| Negative capability probes and four-target `run.sh` | Implemented |

Each Node owns one private Incr Query Region. Number, Boolean, and OptionalOffset parameters are typed Sources; Add, Multiply, SafeDivide, and OptionalOffset own typed binding Sources and derived outputs. OptionalOffset distinguishes an absent optional Input from a connected unavailable provider. Publication creates runtime definitions before installing graph state, and stages binding writes in one transaction. Every Surface Snapshot projects deterministic Node, Port, Parameter, Action, and Connection views independently of Output demand. Surface output and Action demand is deduplicated in first-occurrence order; unavailable outputs and Action inputs carry immutable ordered issues, while formula failures remain current values. Display exposes a pass-through Number output and an explicit RecordNumber Action; availability never invokes it.

## Question

Can one opaque, UI-framework-neutral Nodeflow aggregate provide typed dynamic graph edits, Formula evaluation, explicit Actions, Region lifetime, Graph Document restoration, and Surface Snapshots using only the public Incr Query interface?

## Public evidence seam

The black-box consumer imports Nodeflow but not Incr Query. It exercises `apply`, `snapshot`, `invoke`, `document`, `restore`, and `close`. Graph Transition, Store, Region, Source, View, QueryContext, runtime capability sums, Action preparation, and Graph Document wire records remain private. White-box tests are limited to Formula invocation counts, Action invocation counts, dependency retirement, Region closure, quarantine cleanup, and restoration non-replay.

## Validation

Run from the repository root:

```bash
bash examples/spikes/incr_query_nodeflow_kernel/run.sh
```

The harness checks formatting and generated-interface freshness, then checks and tests the provider and public consumer on default, native, JavaScript, and wasm-gc targets. It runs imported-package negative probes, verifies the consumer does not import Incr Query, verifies the generated Nodeflow interface contains no kernel representation, confirms the Incr Query interface hash is unchanged, and runs repository layout and documentation boundary checks.

## Current result

The implemented boundary matrix passes on all four targets. The prototype demonstrates an operation-based optional layer without a public typed-capability registry, whole-document interactive replacement, automatic Action execution, or Incr Query kernel changes. Final Adoptable/Promising/Reject disposition remains pending the repository-wide validation and final independent review.

## Constraints

- The descriptor set and Formula implementations are closed evidence, not a production plugin model.
- Graph Identity issuance and live-owner exclusion are process-local evidence. Identity-preserving restoration requires the prior aggregate to close; distributed issuance and graph clone policy are not established.
- Commands are immutable returned values only. No interpreter, feedback scheduler, retry, cancellation, idempotency, or external I/O is implemented.
- Graph Document JSON is an evidence schema, not a published compatibility commitment or persistence storage engine.
- Output demand controls observation, not cache eviction.
- Canopy Canvas, Layout Profile, Presentation State, collaboration, undo/redo, CRDTs, and distributed execution remain outside this spike.
