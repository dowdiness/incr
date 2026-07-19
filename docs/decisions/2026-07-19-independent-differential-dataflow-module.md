# ADR: Independent differential dataflow module boundary

**Date:** 2026-07-19

**Status:** Accepted; the Phase 0 correctness spike passed with a bounded GO, but a production engine is not commissioned

**Phase 0 implementation and evidence:** [Retractable dataflow correctness spike](../../dataflow/README.mbt.md)

**Reader:** Maintainers deciding where temporal, differential, or distributed dataflow work belongs.

**Decision:** Keep the Phase 0 correctness spike as an independent in-workspace module, not as another `incr` cell kind.

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

The Phase 0 spike created an experimental workspace module named
`dowdiness/dataflow`, analogous to `incr_tea` in workspace placement but not in
purpose or dependencies.

`dataflow`:

- has no dependency on `dowdiness/incr`;
- has no dependency on Event Graph Walker;
- remains unpublished and carries no API-stability promise during the spike;
- owns dataflow update, operator, worker, progress, and arrangement semantics;
- treats real networking and parallel execution as future shells around the
  same worker/message model.

It is not an `incr` cell kind and does not weaken `incr`'s closed cell taxonomy
or scheduler boundary.

### 2. Integrate through one-way adapters

Future adapters are separate, provisional modules:

```text
dataflow <- incr_dataflow -> incr
dataflow <- event_graph_dataflow -> event-graph-walker
```

Phase 0 does not create either adapter. Their names and public APIs remain
provisional and require separate commissioning and review.

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
ADR. The Phase 0 GO accepts only the bounded correctness result below.

## Phase 0 result

The 2026-07-19 result is **GO for the bounded correctness semantics**. The
private implementation consolidates and validates the complete source epoch
before authorizing any worker envelope. Invalid multiplicity rejects the epoch
without changing worker, source, or materialized state. Accepted zero-crossing
edge changes select affected origins from the previous closure and rebuild only
those origins through worker-routed keyed joins and thresholded feedback.
Cycles terminate because each worker admits a reachable pair once per rebuild,
not once per path.

The worker core is reducer-shaped: it deep-copies nested maps and sets, applies
one deterministic event, and returns a next state plus owned decisions. A
second pure reducer owns every epoch transition and returns an immutable phase
plus a lifecycle decision; the shell applies decisions and owns seeded
scheduling, transport, mailboxes, traces, and publication effects. Persistent
Core vectors retain staged state without mutating prior epoch phases.
Complete source validation converts raw signed updates into exact absent or
positive edge multiplicities before worker application. A single envelope
parser checks the draining epoch, sender role, worker identity, positive
multiplicity, and key ownership, then produces a routed-event variant whose
former operator/port/event combinations
cannot conflict. Transport, mailboxes, traces, and reducers accept only that
parsed form. For completion, the shell gathers transport, mailbox, expected
worker count, worker identity, and close facts. A pure parser requires exact
participant coverage before producing the evidence used to construct the
completed epoch consumed by publication. The shell retains
only the last defensive publication snapshot and a count; it does not
accumulate publication history.

Acceptance evidence is retained in the [module README](../../dataflow/README.mbt.md):
20 correctness tests include every required table case, pure lifecycle and
completion probes, and 40-success bounded
generated traces compare N=1/2/4 workers and randomized batching/delivery with an
independent full-recomputation oracle, same-seed decision traces replay equally,
and copied-buffer and no-early-publication probes pass; the full workspace
suite and boundary scripts also pass, while the generated package interface
contains no public values, types, errors, or traits.

The bounded implementation recomputes affected origins after source-membership
changes; it does not claim a general differential algorithm, stable API,
performance threshold, or production readiness. Two release-mode benchmark
cases were recorded without optimization.

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

A document-keyed EGW projector remains a valid simpler fallback. It would have
been the no-go result if the spike had required EGW-specific behavior or failed
recursive retraction.

### Start in a separate repository — deferred

The in-workspace module keeps CI and boundary experiments cheap. Extraction,
publishing, or independent versioning requires a later identity decision and,
if it changes this boundary, a superseding ADR.

## Consequences

- The repository has a `dataflow/` workspace member with a reader-facing README,
  workspace-mode CI coverage, and boundary validation.
- The module remains unpublished and intentionally exposes an empty generated
  package interface while the API is provisional.
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

The workspace now contains the unpublished `dowdiness/dataflow` spike, but its
generated package interface is empty. `incr` and EGW receive no API change. The
GO result authorizes no package publication, compatibility promise, adapter, or
production runtime.

## Follow-up gates

1. Before any consumer integration, separately commission and review a minimal
   MoonBit API; the Phase 0 private types are not accepted automatically.
2. Only after that API review, separately commission an `incr_dataflow` adapter.
3. Only after an Incr adapter is evaluated, separately commission EGW as a
   second workload through its supported public boundary.
4. Do not begin networking, checkpointing, capability, or partial-order-time
   work without a named workload that exceeds the local/virtual-worker model.
5. Revisit module identity, publication, and extraction only with a real
   consumer and a superseding or updated decision.
