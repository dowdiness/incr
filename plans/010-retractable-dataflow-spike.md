# Plan 010: Build a retractable dataflow correctness spike

> **Executor instructions:** Follow the plan in order. Run each validation gate
> before continuing. Stop on any condition listed under **STOP conditions**;
> do not widen semantics or add adapters to make a failing spike appear to
> pass. Update the Plan 010 row in `plans/README.md` when work begins or ends.

## Status

- **Priority:** P1
- **Effort:** L
- **Risk:** HIGH (new recursive-retraction and progress semantics)
- **Depends on:** none; independent of Plans 008–009
- **Category:** architecture/correctness spike
- **Commissioned by:** operator request on 2026-07-19

**Reader:** The implementer and reviewer of the first `dowdiness/dataflow` spike.

**Decision:** Implement only the bounded correctness experiment defined below; do not build adapters or real distribution.

**Keep until:** The spike receives an accepted go/no-go result.

**Disposition:** On completion, record the result in the ADR and durable module docs or a dated evidence note, update `plans/README.md`, then delete this plan under the documentation retention policy. Git history remains the recovery path.

Decision record:

- [ADR: Independent Differential Dataflow Module Boundary](../docs/decisions/2026-07-19-independent-differential-dataflow-module.md)

Design authority:

- [Differential Dataflow Core — Phase 0 Semantic Specification](../docs/design/specs/2026-07-19-differential-dataflow-core.md)

## Why this matters

Current Incr Datalog proves that typed relations and semi-naive fixed points are
useful, but it is insert-only and local. Adding distribution or CRDT adapters
before defining recursive retraction would hide the hardest semantic question
under transport and integration work.

This spike is intentionally falsifiable. It must either demonstrate correct,
deterministic set reachability under signed edge updates across isolated
virtual workers or stop the general dataflow direction before it accumulates a
public API and adapter dependencies.

## Current state and drift check

Before editing, verify the source assumptions in the design specification:

- `incr/cells/datalog_relation.mbt`: `current`/`delta`/`staged_delta`, insert-only
  relation behavior;
- `incr/cells/internal/kernel/fixpoint.mbt`: local semi-naive convergence loop;
- `incr/cells/datalog_rule.mbt`: declared input/output IDs and opaque rule
  closure;
- `incr/cells/internal/kernel/state.mbt`: single-threaded Runtime assumption;
- `incr/cells/internal/kernel/evaluation_strategy.mbt`: sealed strategy bundle;
- `docs/architecture.md`: closed cell/scheduler extension surface;
- `moon.work`, `scripts/check-workspace-boundaries.sh`, and its self-test:
  current workspace-member requirements.

Run and record:

```bash
git status --short
git diff --stat -- moon.work scripts/check-workspace-boundaries.sh \
  scripts/check-workspace-boundaries-selftest.sh
NEW_MOON_MOD=0 moon check
```

If the dataflow module already exists or any source assumption has changed,
stop and reconcile the ADR/spec before implementing.

## Existing API First check

Before introducing a type, helper, loop, or data structure, inspect project and
MoonBit core APIs with `moon ide`.

Required candidates include:

- project `Relation`, `MapRelation`, `Revision`, and `EvaluationStrategies` as
  semantic references that should not be reused as dataflow storage/time;
- core `Map`/`HashMap` for keyed arrangements;
- core `Set`/`HashSet` for finite set views and test oracles;
- `Array`/`ArrayView` and `Iter` for owned batches and traversal;
- `Option`/`Result` for protocol outcomes;
- `cmp`/comparison helpers for canonical output ordering;
- `Bytes`/`BytesView` or `Buffer` only if a local codec becomes necessary
  (network codecs are out of scope).

Use commands such as:

```bash
NEW_MOON_MOD=0 moon ide doc "Map::*"
NEW_MOON_MOD=0 moon ide doc "HashMap::*"
NEW_MOON_MOD=0 moon ide doc "HashSet::*"
NEW_MOON_MOD=0 moon ide doc "Array::*"
NEW_MOON_MOD=0 moon ide doc "Iter::*"
NEW_MOON_MOD=0 moon ide doc "Option::*"
NEW_MOON_MOD=0 moon ide doc "Result::*"
NEW_MOON_MOD=0 moon ide outline incr/cells
```

Record which APIs are reused and why any new helper remains necessary. Do not
copy Incr's Runtime, `CellId`, or revision types into the new module.

## Scope

### In scope

- one experimental `dowdiness/dataflow` workspace module;
- its required reader-facing README;
- a total private `Epoch(Int)` model;
- explicit epoch close and local global-completion detection;
- private worker/operator/port identities;
- copied or owned message envelopes;
- a pure reducer-shaped worker/operator core;
- a thin deterministic/randomizable local scheduler and transport shell;
- signed integer edge multiplicities and ingress consolidation;
- keyed arrangements sufficient for the reachability join;
- join, concat, feedback, and recursive threshold/distinct;
- canonical materialization and output deltas at closed epochs;
- a full-recomputation reachability oracle;
- deterministic and property tests at N=1, N=2, and N=4;
- release-mode measurement only after correctness is complete.

### Out of scope

- changes to `incr` production code or public API;
- a new Incr cell kind;
- `incr_dataflow` or Event Graph Walker adapter code;
- Event Graph Walker public or internal API changes;
- threads, processes, sockets, Web Workers, or remote execution;
- checkpointing, durable replay, exactly-once delivery, failure recovery,
  dynamic resharding, placement optimization, or backpressure tuning;
- generic partial-order timestamps, antichains, or user-held capabilities;
- arbitrary Datalog parser/lowering or public operator-builder APIs;
- publication, semver promises, issue creation, or pull-request creation.

## Expected file boundary

Determine exact package files after the Existing API First check. The change is
expected to include only:

- `moon.work`;
- a new `dataflow/` module, package source, tests, generated interfaces, and
  `README.mbt.md` or README matching repository policy;
- workspace boundary scripts/self-tests only if the current checks require a
  new explicit member rule;
- `.github/workflows/ci.yml`, adding the new member to a workspace-mode
  check/test job or matrix that enumerates every `dataflow/**/moon.pkg`;
- this plan/index and documentation links required by the repository workflow.

Do not edit `incr/cells/**`, `incr/types/**`, `incr_tea/**`, examples, or the
Event Graph Walker submodule.

## Step 1: Scaffold the independent module

1. Add `dataflow/` as a workspace member with its own MoonBit module identity.
2. Give it no dependency on `dowdiness/incr` or Event Graph Walker.
3. Add the required module README stating experimental status, the Phase 0
   scope, validation commands, and lack of compatibility/publication promise.
4. Update workspace-boundary validation and its self-test only if inspection
   shows that a new member otherwise escapes or violates existing checks.
5. Update `.github/workflows/ci.yml` so a workspace-mode job or matrix entry
   enumerates every package under `dataflow/` and runs both `moon check` and
   `moon test`; the current library/docs jobs do not cover a new root member.
6. Keep the public package surface empty or minimal; conceptual spec names are
   not automatically public APIs.

Verify:

```bash
NEW_MOON_MOD=0 moon check
bash scripts/check-workspace-boundaries.sh
bash scripts/check-workspace-boundaries-selftest.sh
```

## Step 2: Define the private update and progress model

Implement the smallest internal values and pure transitions required for:

- total epochs with exactly one open or draining epoch;
- signed updates;
- deterministic consolidation by `(data, epoch)`;
- explicit source close;
- rejection of updates after close;
- rejection of `e + 1` input until `e` is globally complete and published;
- staging of the full source epoch before propagation;
- consolidation and nonnegative-multiplicity validation before mutating any
  arrangement or operator state;
- atomic invalid-epoch rejection that discards staged work, preserves the last
  completed source and derived state, publishes nothing, and permits the next
  epoch to open;
- canonical output ordering.

Pin invalid-epoch atomicity and the recoverable error behavior with unit tests.
Do not add generic timestamp, lattice, antichain, capability, serialization, or
network abstractions.

Verify with package tests and `NEW_MOON_MOD=0 moon check`.

## Step 3: Build worker isolation and the local shell

1. Define opaque worker-owned state and stable logical routing identities.
2. Define owned immutable envelopes or copy defensively on enqueue.
3. Implement a deterministic reducer boundary of state plus event to next state
   plus decisions.
4. Implement the local scheduler/transport as the only owner of mailboxes and
   delivery order.
5. Add a randomized scheduler mode with a recorded seed for reproducible test
   failures.
6. Add an isolation test: mutating a caller-owned batch after enqueue must not
   change queued work or results.

No worker may read another worker's arrangements or mutable collections.

## Step 4: Implement arrangements and non-recursive operators

Add only the private operators needed by the driver:

- key exchange across virtual workers;
- keyed arrangement;
- join;
- concat;
- consolidation;
- threshold/distinct;
- materialization/inspect after close.

Test duplicate updates, zero-net batches, batch permutation, and key routing
before introducing feedback.

## Step 5: Add finite recursive reachability

Implement the two reachability rules from the spec. Apply threshold/set
semantics at the recursive variable so cycles do not generate unbounded path
multiplicity.

Required table cases:

- empty graph;
- one edge;
- a chain;
- duplicate insertion and partial retraction;
- two alternate paths followed by removal of one path;
- removal of the final supporting path;
- self-cycle;
- multi-node cycle;
- cycle connected to an acyclic tail;
- mixed insertion and deletion in one epoch.

Every case must terminate and match full set recomputation after close.

## Step 6: Add the full-recomputation oracle

The oracle owns a simple positive-membership edge set and recomputes ordinary
finite transitive closure from scratch after each closed epoch. It must not use
incremental operator or arrangement code.

For every deterministic and generated trace, compare:

- canonical reachable set;
- canonical output delta from the prior closed epoch;
- source multiplicities where exposed to the test harness;
- completion epoch.

A mismatch is a STOP condition, not a reason to weaken the oracle.

## Step 7: Exercise virtual-worker and delivery independence

Run identical bounded traces with:

- N=1, N=2, and N=4 workers;
- deterministic delivery;
- randomized delivery order;
- randomized input batch boundaries;
- repeated replay with the same random seed.

Require equal canonical outputs and oracle equality for every closed epoch.
Assert that no materialization is published before all worker mailboxes,
transport messages, and feedback work for that epoch are drained. Assert that
input for `e + 1` cannot affect state or output for `e`.

For replay with the same worker count and scheduler seed, also compare a
canonical decision trace: normalized envelopes, progress transitions, and
materialization decisions. Different worker counts or different random seeds
need equal outputs, not identical internal routing traces.

## Step 8: Validate, inspect interfaces, and measure only after correctness

Run in this order from the repository root:

```bash
NEW_MOON_MOD=0 moon fmt
NEW_MOON_MOD=0 moon info
git diff -- '*.mbti'
NEW_MOON_MOD=0 moon check
NEW_MOON_MOD=0 moon test
bash scripts/check-engine-isolation.sh
bash scripts/check-workspace-boundaries.sh
bash scripts/check-workspace-boundaries-selftest.sh
```

Inspect generated interface diffs. The spike should expose no accidental
public operator/storage API.

After all correctness gates pass, add or run the smallest release-mode
microbenchmark that compares bounded N=1 and virtual-worker execution. Record
the result without optimizing or inventing a threshold. Any optimization must
begin with a separate performance investigation and reproducible benchmark.

## Test plan

### Unit tests

- consolidation and zero-net removal;
- negative source multiplicity rejects the entire epoch before propagation;
- rejected epochs preserve the prior source/derived state, publish nothing,
  and allow a later valid epoch to complete;
- update-after-close rejection;
- threshold transitions around zero;
- arrangement update and join behavior;
- copied-envelope isolation;
- epoch completion and no early publication.

### Table tests

All graph shapes listed in Step 5, including duplicate support, alternate
paths, deletions, and cycles.

### Property tests

Generate bounded node sets, edge update batches, and epoch traces. At every
closed epoch:

- source multiplicity is nonnegative at every accepted epoch;
- rejected epochs leave the prior oracle and incremental state unchanged and
  emit no output;
- incremental output equals the independent full-recomputation oracle;
- N=1/2/4 canonical results agree;
- input and delivery permutations agree;
- input for a later epoch cannot contaminate the active epoch;
- replay with the same worker count and seed has an equal canonical decision
  trace and output.

Keep generators bounded so failures shrink to readable graph/update traces.

## Go/no-go criteria

### Go

All must hold:

- every closed epoch equals the full-recomputation oracle;
- no output is published before epoch completion;
- canonical output is independent of worker count, delivery order, and batch
  splitting;
- replay with the same worker count and seed produces an equal canonical
  decision trace;
- later-epoch input cannot affect an earlier epoch;
- invalid epochs are rejected atomically before propagation and do not block a
  later valid epoch;
- no mutable state is reachable across workers or through caller-owned queued
  buffers;
- cyclic retractions terminate under finite set semantics;
- no Event Graph Walker or Incr-specific behavior appears in core operators;
- generated public interfaces contain only an intentionally reviewed minimal
  spike surface.

### No-go

Record no-go and stop the general engine direction if any of these remains
after reducing the failing case:

- recursive retraction cannot be expressed without unbounded path
  multiplicity or domain-specific exceptions;
- correct completion requires shared mutable state between workers;
- results depend on worker count or delivery order;
- the independent oracle cannot be kept simpler than the incremental engine;
- the core requires CRDT-specific version or merge semantics.

The fallback is a document-keyed EGW projector and existing Incr integration,
not a broader dataflow runtime.

## STOP conditions

Stop and report without expanding scope if:

- source assumptions or workspace boundary scripts have drifted materially;
- a proposed package must import `dowdiness/incr` or EGW to implement the core;
- a test needs raw EGW local LVs or EGW `internal/` APIs;
- a closed epoch emits before all work is drained;
- cycles fail to terminate or produce multiplicity-dependent set output;
- any N=1/2/4 or delivery-order comparison differs;
- defensive-copy/ownership tests reveal cross-worker aliasing;
- `moon info` exposes an unreviewed public API;
- validation requires modifying existing Incr production code.

## Done criteria

- [ ] New independent module exists and is included in `moon.work`.
- [ ] Module README states experimental scope and validation commands.
- [ ] No dependency on Incr or Event Graph Walker.
- [ ] Unit, table, and property tests cover every required semantic law.
- [ ] N=1/2/4 and randomized delivery/batching match the oracle.
- [ ] No early publication or cross-worker mutable aliasing.
- [ ] CI includes a workspace-mode `dataflow` package check/test entry.
- [ ] Full validation commands pass.
- [ ] `.mbti` diffs are intentional and reviewed.
- [ ] Go/no-go result is recorded in the ADR and durable module docs/evidence.
- [ ] Documentation retirement steps below are complete.

## Documentation disposition

After the go/no-go result is accepted:

1. Update the ADR with the result and any changed boundary.
2. Distill stable go semantics into the module README/package docs, or record
   the no-go rationale durably in the ADR.
3. Delete this plan and delete the time-bounded spec when it no longer
   describes active work.
4. Remove the direct Plan 010 and spec entries from `docs/README.md` and repair
   surviving links.
5. Remove the Plan 010 row from `plans/README.md`; do not leave a completed-plan
   tombstone there.

Git history remains the recovery path. The ADR remains durable and is marked
superseded rather than deleted if a later decision replaces it.

## Validation and repository notes

This repository is itself consumed as a submodule by Loom/Canopy. Plan 010
changes only this repository until a later adapter is commissioned. Before any
parent-pointer update, validate the parent workspace separately and follow the
submodule push-before-pointer workflow. Plan 010 does not authorize a push,
pull request, release, or parent-pointer change.

No proof package or TypeScript/web validation is required unless execution
introduces one, which would first require revising this plan's scope.
