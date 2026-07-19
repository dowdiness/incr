# Differential dataflow core — Phase 0 semantic specification

**Date:** 2026-07-19

**Status:** Proposed semantics for Plan 010; no public API is accepted

**Decision record:** [Independent Differential Dataflow Module Boundary](../../decisions/2026-07-19-independent-differential-dataflow-module.md)

**Implementation plan:** [Plan 010: Retractable dataflow spike](../../../plans/010-retractable-dataflow-spike.md)

**Reader:** Implementers and reviewers of the first `dowdiness/dataflow` correctness spike.

**Decision:** Define the smallest local, worker-isolated differential model that can falsify retractable recursive reachability before any adapter or network work.

**Keep until:** The Plan 010 go/no-go result is accepted.

**Disposition:** On go, distill stable semantics into module/package documentation and delete this time-bounded spec when it no longer describes active work. On no-go, record the rejected direction in an ADR update and delete this spec; Git history remains the recovery path.

## Purpose

This specification describes a correctness experiment, not a Timely Dataflow
port and not a production distributed runtime. The experiment asks whether a
small MoonBit core can maintain set-valued recursive reachability under
insertions and deletions while preserving deterministic behavior across
isolated virtual workers.

The design is deliberately narrower than the eventual ambition:

- time is a total input epoch;
- progress is an explicit epoch-close protocol;
- workers run in one process through a local scheduler;
- operators are a minimal closed spike vocabulary;
- failure recovery and durable execution are absent.

Names and signatures below are conceptual. They do not define accepted public
MoonBit APIs.

## Phase 0 at a glance

| Concern | Phase 0 rule |
|---|---|
| Time | One total `Epoch(Int)` may be open or draining |
| Input | Stage, consolidate, and validate the whole epoch before propagation |
| State | Invalid epochs leave the last completed state unchanged |
| Execution | Opaque virtual workers exchange owned/copied envelopes |
| Recursion | Keyed join plus feedback, thresholded to finite set semantics |
| Completion | Publish only after close and global local-transport quiescence |
| Validation | Compare every closed epoch with full recomputation at N=1/2/4 |

## Verified starting point

The spike is separate because the current Incr model does not already provide
these semantics:

- `Relation[T]` stores `current`, `delta`, and `staged_delta` HashSets and only
  inserts facts (`incr/cells/datalog_relation.mbt`).
- The fixpoint kernel drains the local frontier, invokes every live rule, and
  repeats while a local staged delta is non-empty
  (`incr/cells/internal/kernel/fixpoint.mbt`).
- Rules expose declared input/output IDs but execute an opaque closure
  (`incr/cells/datalog_rule.mbt`).
- Runtime tracking is explicitly single-threaded
  (`incr/cells/internal/kernel/state.mbt`).
- Evaluation strategy selection serves sealed diagnostic wrapping and offers
  no public scheduler extension
  (`incr/cells/internal/kernel/evaluation_strategy.mbt`).
- Current research records no general fact/key retraction or provenance
  (`docs/research/2026-07-14-bonsai-informed-incr-core-direction.md`).

These are reusable reference behaviors and tests, not implementation types for
the new core.

## Goals

Phase 0 must establish:

1. deterministic signed-update processing at closed epochs;
2. worker-local opaque state and message-only interaction;
3. keyed partitioning and arrangements sufficient for a binary join;
4. finite set-valued recursive reachability with insertions and deletions;
5. canonical results independent of worker count, delivery order, and batch
   boundaries;
6. a full-recomputation oracle after every closed epoch;
7. a functional core with scheduling and lifecycle effects in a thin shell.

## Non-goals

Phase 0 does not provide:

- threads, processes, sockets, Web Workers, or remote execution;
- checkpointing, replay logs, failure recovery, exactly-once transport, or
  dynamic resharding;
- generic partial-order timestamps, antichain frontiers, or user-held
  capabilities;
- Timely or Differential Dataflow API/wire compatibility;
- a public/stable operator API;
- arbitrary Datalog lowering;
- incremental aggregation beyond what the reachability driver requires;
- Incr or Event Graph Walker adapters;
- CRDT merge, causal completeness, replica membership, or causal-history GC;
- performance optimization before a release-mode microbenchmark identifies a
  material bottleneck.

## Truth and state ownership

The core owns only rebuildable derived computation state:

- worker mailboxes;
- operator state;
- keyed arrangements;
- per-epoch progress state;
- canonical output deltas and materializations.

It does not own application truth. A future input source or host adapter owns
its authoritative data and may rebuild the dataflow state.

For the anticipated integrations:

- EGW owns CRDT operations, causal graph, conflict resolution, and
  convergence.
- Incr owns cells, dependency traces, revisions, and application/UI caches.
- Dataflow owns derived arrangements, progress, and partitioning.

## Three independent time domains

The design must keep these domains distinct:

| Domain | Meaning | May move backward? |
|---|---|---|
| Incr `Revision` | Cache invalidation and verification metadata | No |
| EGW causal version/heads | A position or tip set in the event DAG | A branch query may move to an earlier or concurrent version |
| Dataflow `Epoch` | Closed input batch and publication boundary | No |

Phase 0 uses a total conceptual `Epoch(Int)`. Inputs for epoch `e` may be
processed in any order, but results for `e` are not externally complete until
all input handles close `e` and all transitively produced work for `e` is
drained.

Only one epoch may be open or draining in Phase 0. The shell rejects input for
`e + 1` until `e` is globally complete and published, so later updates cannot
enter shared arrangements or contaminate the materialization for `e`.
Pipelined epochs and per-epoch state isolation remain future work.

Generic timestamp partial orders and capabilities are deferred. The spike must
not expose an API that claims their semantics.

## Update algebra

A conceptual update is:

```text
(data, epoch, diff)
```

where `diff` is an integer multiplicity change.

### Consolidation

For equal `(data, epoch)`, ingress and operator boundaries sum diffs. A net zero
update is discarded. Consolidation must be deterministic and independent of
batch splitting.

### Source multiplicity

The edge input is a multiset. Duplicate insertion increases multiplicity;
retraction decreases it. Source updates for the active epoch remain staged
until close. At close, the shell consolidates the full source batch and
validates each resulting source multiplicity against the last completed state
before any arrangement or operator state is mutated.

A resulting source multiplicity below zero rejects the epoch. Rejection
discards all staged updates and decisions for that epoch, preserves the last
completed source and derived state, emits no materialization, and permits the
next epoch to open. The exact recoverable error representation remains an
implementation decision; silent clamping is forbidden.

### Set threshold

Reachability is set-valued. For a valid consolidated support multiplicity `m`:

- `m < 0` is an invariant or protocol error;
- `m == 0` means absent;
- `m > 0` means present.

The transition across zero emits the corresponding `-1` or `+1` set update.
Changes that do not cross zero emit no set change.

This threshold is required for duplicate edges and alternate paths. Removing
one support must not remove a reachable pair while another support remains.

## Minimal operator vocabulary

The spike may use a private, closed vocabulary sufficient for the driver:

- input;
- key-preserving map/projection where required by the plan;
- keyed exchange between virtual workers;
- arrangement by key;
- binary join;
- concat/union of update streams;
- consolidate;
- threshold/distinct;
- feedback into the recursive variable;
- materialize/inspect at a closed epoch.

Adding general reducers, windows, arbitrary user operators, or public builder
syntax is out of scope.

## Arrangements

An arrangement is worker-owned indexed state derived from consolidated
updates. For Phase 0 it must support the join keys required by reachability and
must not be observable as a mutable collection outside its owning worker.

Required properties:

- updates are applied once after consolidation;
- lookup order does not affect canonical output;
- duplicate support is represented by multiplicity rather than duplicate
  storage assumptions;
- arrangements can be rebuilt from authoritative input history used by the
  test oracle;
- no arrangement object or mutable backing collection crosses a worker
  boundary.

Compaction across historical epochs is deferred. The test may retain all
state required by its bounded traces.

## Recursive reachability semantics

Given an edge relation `edge(x, y)`, the target relation is the finite set:

```text
reachable(x, y) :- edge(x, y)
reachable(x, z) :- reachable(x, y), edge(y, z)
```

The recursive variable is thresholded to set semantics on each feedback round.
The engine must not count an unbounded number of paths around a cycle. A fact
already present in the recursive set is not fed back as a new path merely
because another cyclic derivation exists.

The fixed point for a closed epoch is reached when:

1. no worker has a runnable update for that epoch;
2. no envelope for that epoch is in the local transport;
3. all feedback updates have been consolidated and thresholded; and
4. no threshold crossing produced further work.

The full-recomputation oracle computes ordinary set reachability from the
source edge multiset's positive-membership projection after each epoch. The
incremental materialization must equal that oracle for insertions, duplicate
support, alternate paths, retractions, and cycles.

## Progress and publication

Phase 0 progress implements an explicit local close protocol. General Timely
capabilities remain deferred.

- Inputs announce that the single active epoch is closed.
- Closing is monotone; a source cannot later submit an update for a closed
  epoch.
- Input for a later epoch is rejected until the active epoch is globally
  complete and published.
- A worker may report local idleness, but the scheduler declares global epoch
  completion only after every worker mailbox and the transport are drained for
  that epoch.
- Materialized output for epoch `e` is published only after global completion
  of `e`.

No observation of a partially processed epoch may be labelled complete.
Future networking must preserve this contract before introducing distributed
progress accounting.

## Functional core and imperative shell

The core should have a reducer-shaped boundary conceptually equivalent to:

```text
WorkerState + WorkerEvent -> WorkerState + Decisions
```

`WorkerEvent` includes delivered update batches and epoch-close information.
`Decisions` include output envelopes, local scheduling requests, progress
changes, and closed-epoch materialization events.

The reducer:

- is deterministic;
- reads no clock, random source, filesystem, network, or global Runtime;
- owns all mutation used to build its returned state/decisions;
- never sends or stores references to another worker's mutable state.

The imperative shell:

- owns mailboxes and scheduling;
- copies or transfers owned message values;
- selects deterministic or randomized delivery order for tests;
- executes decisions and reports protocol errors;
- will be the future location of threads, transport, cancellation, and
  persistence.

## Worker and message isolation

MoonBit values can alias mutable arrays and objects, so package separation
alone is insufficient.

Phase 0 requires:

- opaque worker and arrangement types;
- owned immutable messages or defensive copies at enqueue time;
- no exposed `Array`, `Map`, document, snapshot, or arrangement that aliases
  worker state;
- stable worker/operator/port identities in envelopes, independent of memory
  addresses;
- canonical comparison of output values rather than iteration order.

A test-only isolation probe must show that mutating caller-owned input buffers
after enqueue cannot change queued work or worker state.

## Provisional package dependency graph

The target direction is:

```text
dowdiness/dataflow
  ^                 ^
  |                 |
incr_dataflow   event_graph_dataflow
  |                 |
dowdiness/incr  dowdiness/event-graph-walker
```

Only `dowdiness/dataflow` is in Plan 010. Adapter module names are provisional.
No host library depends on an adapter or on the core.

## Future Incr adapter contract

A later `incr_dataflow` design should:

- publish only frontier-complete materializations;
- translate one completed dataflow epoch into one `Runtime::batch` publication
  boundary;
- own created Incr cells in a `Scope`;
- dispose the dataflow handle before scope teardown;
- keep dataflow time out of `Revision` and keep `Revision` out of progress;
- expose defensive values rather than internal arrangements.

These are follow-up constraints, not Plan 010 implementation scope.

## Future EGW adapter contract

EGW's package boundary is authoritative. An external adapter cannot import or
construct its internal `OpLog`, `Branch`, `CausalGraph`, or `FugueTree` types.
For text, the supported boundary is `TextState::sync()` for ingestion and
`TextState::causal_snapshot()` for causal inspection. `CausalSnapshot` aliases
the live graph, so the adapter shell must read one observation into an owned
array: map each LV from `CausalSnapshot::frontier()` through
`entry(lv).agent()` and `entry(lv).seq()`, copy those stable identities, and
sort the copy before enqueue. Neither the live snapshot nor its borrowed views
may cross a worker or message boundary.

The public container `Document` supports sync ingestion but does not currently
expose a causal snapshot. A document-level adapter that needs canonical heads
therefore requires a separately reviewed EGW public projection API. It must not
reach through `internal/`.

EGW's identifiers must not be conflated:

- a local LV is allocated by arrival order and is not stable across replicas;
- `(agent, seq)` identifies an operation across replicas;
- a CRDT causal-head set describes version state;
- a dataflow progress frontier describes execution completion.

Cross-delivery acceptance tests compare sorted canonical `(agent, seq)` heads,
not raw LV frontiers. This corrects the proposed adapter oracle; it does not
identify a defect in existing EGW tests.

Dataflow epoch completion is not proof of CRDT convergence. Publication that
claims causal completeness requires either a causally closed input batch or a
separate causal-completeness status from the adapter.

## Error and lifecycle boundaries

The spike must use structured, deterministic errors for invalid source
multiplicity, updates after close, invalid routing identities, and protocol
violations. Rejecting an invalid epoch is recoverable and atomic: it discards
that epoch's staged work, preserves the last completed state, publishes
nothing, and allows the next epoch to open. Invariant defects may abort only
where repository conventions permit; tests must not rely on partial state
after an abort.

Worker teardown belongs to the shell. Teardown must stop new enqueue, drain or
reject outstanding work according to one explicit policy, and release
worker-owned state without exposing it. Production cancellation and recovery
are deferred.

## Validation laws

The spike is acceptable only if all laws hold for bounded generated traces:

1. **Oracle equality:** every closed epoch materialization equals full set
   reachability recomputation.
2. **Consolidation:** arbitrary batch splits and within-epoch permutations have
   the same result.
3. **Worker independence:** N=1, N=2, and N=4 produce equal canonical output.
4. **No early completion:** no epoch result is published before all work for
   that epoch is drained.
5. **Retraction correctness:** deleting one of several supports preserves a
   fact; deleting the final support retracts it.
6. **Cycle finiteness:** cyclic graphs terminate with finite set output.
7. **Isolation:** no mutable state is reachable across workers or from queued
   caller-owned buffers.
8. **Replay determinism:** replaying the same epoch trace with the same worker
   count and scheduler seed produces equal canonical decision traces and
   outputs.
9. **Epoch isolation:** input for `e + 1` cannot affect arrangements, decisions,
   or materialization for `e`.
10. **Epoch rejection atomicity:** an invalid epoch emits no output, leaves the
    last completed source and derived state unchanged, and does not prevent a
    later valid epoch from completing.

## Open decisions

Plan 010 must resolve or explicitly defer:

- the exact private MoonBit representation of `Epoch`, update weights, and
  protocol errors;
- the recoverable error representation returned for an atomically rejected
  epoch;
- the smallest arrangement representation that supports the driver;
- whether worker/operator identities need generations in the bounded spike;
- how randomized scheduling seeds are recorded for replay;
- what release-mode measurements are useful after correctness, without setting
  an arbitrary optimization threshold;
- the module's long-term name and publication identity after a go result.

## Go/no-go boundary

A go result authorizes design of a reviewed module API and the first Incr
adapter. It does not authorize networking, EGW API changes, publishing, or API
stability.

A no-go result is required if the spike cannot satisfy the validation laws, if
worker isolation requires shared mutable state, or if a core operator must know
EGW-specific semantics. The simpler fallback is a document-keyed EGW projector
and existing Incr integration, not a broader dataflow runtime.
