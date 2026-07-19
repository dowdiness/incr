# ADR: Independent differential dataflow module boundary

**Date:** 2026-07-19

**Status:** Accepted for the module boundary and falsifiable spike; a production engine is not commissioned

**Implementation plan:** [Plan 010: Retractable dataflow spike](../../plans/010-retractable-dataflow-spike.md)

**Design specification:** [Differential Dataflow Core](../design/specs/2026-07-19-differential-dataflow-core.md)

**Reader:** Maintainers deciding where temporal, differential, or distributed dataflow work belongs.

**Decision:** Develop the first correctness spike as an independent in-workspace module, not as another `incr` cell kind.

**Keep until:** Permanently; ADRs are durable and are marked superseded rather than deleted.

**Disposition:** Update this ADR if the spike changes the boundary. Supersede it if the module is abandoned, moved to another repository, or made part of `incr`.

## Context

`incr` combines pull, push, and Datalog evaluation behind one `Runtime`. Its
Datalog engine is a useful driver for incremental relational work, but it is
not a temporal or distributed dataflow substrate:

- `Relation[T]` is set-valued and insert-only for its lifetime. It stores
  `current`, `delta`, and `staged_delta` sets and provides no general
  retraction (`incr/cells/datalog_relation.mbt`).
- The kernel runs one local semi-naive fixpoint over all registered rules and
  stops when local staged deltas are empty
  (`incr/cells/internal/kernel/fixpoint.mbt`).
- A rule stores declared input and output relation IDs plus an opaque
  `apply_delta : () -> Unit` closure. The Runtime cannot inspect the closure's
  partitioning, join, or communication behavior
  (`incr/cells/datalog_rule.mbt`).
- Runtime tracking uses a process-global `Ref` under an explicit
  single-threaded assumption (`incr/cells/internal/kernel/state.mbt`).
- `EvaluationStrategies` is sealed and permits diagnostic wrapping, not a
  public scheduler plug-in (`incr/cells/internal/kernel/evaluation_strategy.mbt`).
- The public cell taxonomy and verification/scheduling policies are closed
  extension surfaces (`docs/architecture.md`).

The Bonsai-informed core-direction research also records that current Datalog
facts are monotonic, that `MapRelation` cannot retract keys, and that a future
differential model requires retraction/provenance semantics not owned by the
current Runtime
(`docs/research/2026-07-14-bonsai-informed-incr-core-direction.md`).

A second prospective driver is Event Graph Walker (EGW). It owns a CRDT
operation log, causal graph, merge semantics, and convergence. Its local
versions, causal heads, and movable branch frontiers are not Timely-style
progress timestamps. A dataflow engine can host derived computation over EGW
updates, but it must not replace or reinterpret the CRDT's source of truth.

## Decision

### 1. Create an independent in-workspace module

The first spike will create an experimental workspace module tentatively named
`dowdiness/dataflow`, analogous to `incr_tea` in workspace placement but not in
purpose or dependencies.

`dataflow` will:

- have no dependency on `dowdiness/incr`;
- have no dependency on Event Graph Walker;
- remain unpublished and carry no API-stability promise during the spike;
- own dataflow update, operator, worker, progress, and arrangement semantics;
- treat real networking and parallel execution as future shells around the
  same worker/message model.

It will not be added as a new `incr` cell kind and will not weaken `incr`'s
closed cell taxonomy or scheduler boundary.

### 2. Integrate through one-way adapters

Future adapters are separate, provisional modules:

```text
dataflow <- incr_dataflow -> incr
dataflow <- event_graph_dataflow -> event-graph-walker
```

Plan 010 does not create either adapter. Their names and public APIs remain
provisional until the core spike passes.

The adapters must not invert ownership:

- EGW remains authoritative for CRDT operations, causal relationships,
  conflict resolution, and convergence.
- `dataflow` owns rebuildable operator state, progress, partitioning, and
  derived indexes.
- `incr` remains authoritative for its application/UI cells, dependency
  tracking, revisions, and cache semantics.

### 3. Keep the three time domains distinct

The design must not identify these concepts:

- `incr` `Revision`: invalidation and verification metadata;
- EGW operation identity and causal heads: CRDT history and version state;
- dataflow logical time and progress: when update batches are complete for an
  execution.

Phase 0 uses only a total `Epoch(Int)` and explicit epoch close. Generic
partial-order timestamps and capabilities remain future design work outside
the first spike.

### 4. Defer distribution machinery, not isolation

The spike uses virtual workers and a local transport. From the first
implementation:

- worker state is opaque and worker-local;
- workers communicate only through owned immutable values or defensive copies;
- the operator core is deterministic and reducer-shaped;
- scheduling and transport are an imperative shell;
- canonical results must not depend on worker count, delivery order, or batch
  boundaries.

Threads, networking, checkpointing, dynamic resharding, placement
optimization, and production fault tolerance are out of scope. The module
makes no Timely API, wire-format, or compatibility claim.

### 5. Gate all further work on a falsifiable spike

The first driver is retractable recursive reachability, not EGW integration.
The spike must define and test integer multiplicity, consolidation,
zero/nonzero set threshold semantics, duplicate edges, alternate paths,
cycles, keyed arrangements, feedback, and termination. Signed records alone
do not satisfy this requirement.

A production or general-purpose dataflow engine is not commissioned by this
ADR. It requires the explicit go decision in Plan 010.

## Rationale

- An independent module makes the dataflow semantic model testable without
  changing `incr`'s Runtime, revision clock, lifecycle, or public API.
- One-way adapters preserve truth ownership and let either host library remain
  useful without the dataflow engine.
- Virtual workers exercise the semantic constraints that are expensive to
  retrofit later, while avoiding premature network and recovery work.
- Retractable recursive reachability is a smaller and more discriminating
  correctness driver than beginning with a specialized CRDT merge engine.
- Keeping EGW as a second workload prevents CRDT-specific causality or merge
  policy from leaking into the core.

## Considered options

### Extend the existing Incr Datalog engine — rejected

This minimizes initial scaffolding, but it would couple temporal progress,
message routing, arrangements, and worker identities to `Runtime`, `CellId`,
`Revision`, and opaque rule closures. The current extension surfaces do not
support that substitution, and the resulting dependency would make a generic
engine unusable without `incr`.

### Build a networked distributed engine first — rejected

Networking would mix transport, serialization, failure, and scheduling defects
with unsettled recursive-retraction semantics. A deterministic local shell over
isolated virtual workers is the cheaper proof.

### Build only an EGW projection service — not chosen as the core direction

A document-keyed EGW projector is a valid simpler fallback. It does not prove a
reusable differential core. It becomes the no-go fallback if Plan 010 requires
EGW-specific behavior or cannot satisfy recursive retraction.

### Start in a separate repository — deferred

The in-workspace module keeps CI and boundary experiments cheap. Extraction,
publishing, or independent versioning requires a later identity decision and,
if it changes this boundary, a superseding ADR.

## Consequences

- The repository will gain a new workspace member only when Plan 010 begins.
  This documentation does not create the module or change `moon.work`.
- The new module will require a reader-facing README and inclusion in workspace
  and boundary validation.
- `incr` receives no new public API or cell kind from this decision.
- EGW receives no public API change from this decision. A text adapter can use
  `TextState::sync()` and `TextState::causal_snapshot()`. The public container
  `Document` supports sync ingestion but does not currently expose a causal
  snapshot; canonical document-level heads would require a separately reviewed
  EGW projection API. No adapter may reach through EGW `internal/`.
- Cross-delivery EGW tests must compare canonical causal heads as sorted
  `(agent, seq)` identities, never replica-local LVs. This is a future adapter
  acceptance rule, not a defect in current EGW tests.
- Dataflow progress completion must never be reported as CRDT causal
  completeness. A future EGW adapter needs causally closed input or a separate
  causal-completeness state.

## Compatibility and API impact

None yet. This ADR and its companion documents are documentation-only. The
accepted boundary authorizes a spike, not a public API, package publication,
or compatibility commitment.

## Follow-up gates

1. Execute Plan 010 and record a go/no-go result.
2. On go, replace provisional conceptual types with a separately reviewed
   MoonBit API and add the module README and package documentation.
3. Only after the core passes, design an `incr_dataflow` adapter.
4. Only after that, test EGW as a second workload through its supported public
   boundary.
5. Do not begin networking or checkpoint work without a named workload that
   exceeds the local/virtual-worker execution model.
