# Nodeflow kernel spike

**Reader:** maintainers evaluating a typed editable semantic graph over Incr Query.

**Decision:** keep Nodeflow opaque and closed while proving typed graph edits and atomic publication.

**Keep until:** Issue #496's finite evidence prototype reaches a documented verdict.

**Disposition:** completed buildable evidence; retain while the optional-layer decision remains active, and delete if a later production design supersedes it.

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

The pure `application` package owns the closed descriptors, metadata, Formula outcomes, calculations, Commands, decisions, and descriptor codec; it imports neither Nodeflow nor Incr Query. The opaque `nodeflow` package lowers that application model into runtime capabilities. Each Node owns one private Incr Query Region. Number, Boolean, and OptionalOffset parameters are typed Sources; Add, Multiply, SafeDivide, and OptionalOffset own typed binding Sources and derived outputs. OptionalOffset distinguishes an absent optional Input from a connected unavailable provider. Publication creates runtime definitions before installing graph state, and stages binding writes in one transaction. Every Surface Snapshot projects deterministic Node, Port, Parameter, Action, and Connection views independently of Output demand. Surface output and Action demand is deduplicated in first-occurrence order; unavailable outputs and Action inputs carry immutable ordered issues, while formula failures remain current values. Display exposes a pass-through Number output and an explicit RecordNumber Action; availability never invokes it.

## Question

Can one opaque, UI-framework-neutral Nodeflow aggregate provide typed dynamic graph edits, Formula evaluation, explicit Actions, Region lifetime, Graph Document restoration, and Surface Snapshots using only the public Incr Query interface?

## Public evidence seam

The black-box consumer imports the application model and Nodeflow but not Incr Query. It exercises `apply`, `snapshot`, `invoke`, `document`, `restore`, and `close`. Graph Transition, Store, Region, Source, View, QueryContext, runtime capability sums, Action preparation, and Graph Document wire records remain private. White-box tests are limited to Formula invocation counts, Action invocation counts, dependency retirement, Region closure, quarantine cleanup, and restoration non-replay.

## Validation

Run from the repository root:

```bash
bash examples/spikes/incr_query_nodeflow_kernel/run.sh
```

The harness checks formatting and generated-interface freshness, then checks and tests the provider and public consumer on default, native, JavaScript, and wasm-gc targets. It runs imported-package negative probes, verifies the consumer does not import Incr Query, verifies the generated Nodeflow interface contains no kernel representation, confirms the Incr Query interface hash is unchanged, and runs repository layout and documentation boundary checks.

## Result: Adoptable optional layer

The implemented boundary matrix passes on default, native, JavaScript, and wasm-gc. Repository-wide validation passes with 1,318 wasm tests and 256 JavaScript tests; the remaining warnings predate this spike. The prototype demonstrates an operation-based optional layer without a public typed-capability registry, whole-document interactive replacement, automatic Action execution, or Incr Query kernel changes.

Independent MoonBit and correctness reviews found no unresolved critical or warning findings after fixes. The packaged four-role parallel review remained formally incomplete because the idioms and API-boundary model providers returned 402 before reading files; a final MoonBit reviewer covered those risks and found the concurrent-restoration identity issue, which was fixed and re-reviewed to PASS.

This verdict authorizes only a separately commissioned optional Nodeflow layer. It does not authorize publication, a production extension model, or any Incr Query kernel change.

## Performance evidence

The [2026-08-29 boundary snapshot](../../../docs/performance/2026-08-29-incr-query-nodeflow-boundaries.md) measures public snapshot, rebind, and demanded-edit operations across wasm-gc, JavaScript, and native. JavaScript remains below 9 ms at 10,000 total nodes for the measured broad/shallow workloads, so no snapshot optimization is justified. The subsequent [production-readiness investigation](../../../docs/research/2026-08-29-nodeflow-production-readiness-options.md) corrects the depth envelope: a cold direct release test passes depth 500 and fails 600 on JavaScript, passes 600 and fails 700 on wasm-gc, and passes at least 10,000 on native. Nodeflow now creates both fresh and restored Stores with a private 256-active-Query limit enforced by the kernel, projecting limit exhaustion as typed Output or Action unavailability rather than allowing a backend stack overflow.

## Constraints

- The application package owns a closed descriptor set and pure Formula implementations. This package boundary is evidence for product-specific models, not a production plugin framework.
- Graph Identity issuance is process-local evidence. Identity-preserving restoration may create concurrent execution domains in the same semantic lineage; references are semantic keys resolved by the explicit Nodeflow receiver, not authority-bearing capabilities. Distributed issuance and merge policy are not established.
- Commands are immutable returned values only. No interpreter, feedback scheduler, retry, cancellation, idempotency, or external I/O is implemented.
- Graph Document JSON is an evidence schema, not a published compatibility commitment or persistence storage engine.
- Output demand controls observation, not cache eviction.
- The measured envelope covers 10,000 broad nodes. Nodeflow fixes a 256-active-Query runtime nesting limit for every Store; this is a stack-safety policy rather than a semantic dependency-depth rejection. A later restartable evaluation design is required only if a product must evaluate deeper cold chains in one root read.
- Canopy Canvas, Layout Profile, Presentation State, collaboration, undo/redo, CRDTs, and distributed execution remain outside this spike.
