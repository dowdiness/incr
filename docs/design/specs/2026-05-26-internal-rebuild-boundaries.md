# Internal Evaluation Boundaries

**Status:** Proposed — ideal design, breaking changes allowed

**Date:** 2026-05-26

**Related:** [Build-oriented boundary design](2026-05-26-build-trait-boundaries.md), [Evaluation Strategy Refactor Plan](../../plans/2026-05-26-evaluation-strategy-refactor.md)

## Goal

Make `incr`'s evaluation machinery explicit enough that downstream systems can
trust it as infrastructure. The ideal design names pull freshness, dependency
verification, pull recompute, push propagation, effect execution, commit, abort
cleanup, GC-root reachability, and observation as separate runtime-owned
responsibilities.

This is allowed to break internal names and narrow public observation names. It
is still **not** a proposal for a public pluggable scheduler. `Runtime` remains
the only scheduler/store coordinator; users build application pipelines with
`Input`, `Derived`, `DerivedMap`, `ReachableDerived`, `EagerDerived`, `Scope`,
and `Watch`.

## North star

The runtime should feel like one small deterministic kernel, not a collection of
special cases hidden in `pull_verify` or `push_propagate_from`.

- **Scheduling is owned by `Runtime`.** External code can observe evaluation,
  but cannot choose freshness, dependency walking, push order, or commit order.
- **Evaluation is a family of state machines.** Pull verification, push
  propagation, effect execution, batching, GC, and fixpoint each need named
  transitions instead of sharing one overloaded "rebuild" concept.
- **Observation is data, not control.** Hooks may receive summaries after safe
  state transitions. They must not run user code while typed caches, phase
  flags, or dependency lists are half-written.
- **Reachability is part of the contract.** `Watch` roots, protected cells, and
  parser attachments rely on `gc_dependencies()` matching the current tracked
  dependencies after a successful compute.
- **Dynamic dependencies are normal.** Changing the set of reads during a
  recompute is a core path, not an edge case.

## What changed after loom lambda and Canopy

The loom lambda and Canopy changes make the ideal boundary sharper:

- `examples/lambda/src/analysis.mbt` introduced `LambdaAnalysis`, a
  language-owned facade that composes parser diagnostics with typecheck output on
  the parser runtime.
- `examples/lambda/src/typed_parser.mbt` now exposes the typecheck result
  `Derived`, while keeping a terminal `Watch` for GC survival.
- Canopy replaced an FFI-local lambda `TypecheckBundle` with the loom-owned
  `LambdaAnalysis` attachment, then exports selected terminal `Derived` cells
  through workspace `ProtectedCell`s.
- Canopy's coordinator validates `gc_root_count`, keeps `Watch` roots alive,
  rejects reads after destroy, and refuses destroy while workspace deps point at
  an editor.

Those are not reasons to expose a scheduler trait. They are reasons to make the
runtime's own rebuild and lifetime transitions auditable. A small mistake in
pull verification can now surface as stale lambda diagnostics, a disposed
protected cell, a leaked workspace dependency, or a GC sweep of parser internals.

## Scope clarification

This document covers `incr` internals:

- freshness decisions,
- dependency recording and dependency diffing,
- pull rebuild execution,
- push propagation and eager recompute,
- effect execution,
- Datalog/fixpoint observation boundaries,
- commit/backdating,
- abort cleanup,
- synthetic accumulator dependencies,
- GC-root reachability,
- runtime event observation.

It does not define application stages such as source loading, parsing,
checking, transformation, provider calls, or build execution. Those belong to
consumer packages and are covered by the companion build-boundary document.

## Build Systems à la Carte mapping

The internal design adopts BSaC's separation of store, trace, scheduler, and
rebuilder, but keeps them behind `Runtime` until their laws are pinned by tests.

| Build Systems à la Carte concept | `incr` internal counterpart |
| --- | --- |
| Store | `RuntimeCore` plus pull/push/datalog SoA state and typed wrapper caches. |
| Task | Cell compute closures installed by `Derived`, `DerivedMap`, `EagerDerived`, `Effect`, and rules. |
| Trace / `Info` | Dependency arrays, subscriber links, `changed_at`, `verified_at`, durability index, accumulator synthetic reads, and push levels. |
| Rebuilder | Pull verification: freshness, dependency scan, synthetic-dep validation, recompute, backdating, and abort cleanup. |
| Scheduler | Evaluation order: demand-driven pull recursion, level-ordered push propagation, batch commit, and fixpoint iteration. |
| Dirty-bit strategy | Push dirty flags plus queue membership. |
| Verifying trace strategy | Pull dependency verification against recorded trace data. |

The important split is internal: **Store and trace representation stay fixed;
scheduler and rebuilder algorithms become sealed runtime strategies.** A strategy
may choose a different traversal or queue discipline, but it must commit through
the same dependency, revision, subscriber, GC-root, accumulator, and phase
protocols.

This gives `incr` the useful BSaC axis of variation without immediately exposing
raw runtime internals as a public plugin API.

## Ideal responsibility map

| Area | Ideal responsibility |
| --- | --- |
| `Runtime` facade | Owns one runtime identity, public handle construction, batching, GC, event sink registration, and thin safe entry points. |
| `RuntimeCore` | Owns revision, phase, tracking stack, cell tables, dispatch tables, batch state, GC roots, and kernel-local transient state. |
| `CellOps` | Internal object-safe cell metadata and graph operations over all cell kinds. Keep fixed-type and internal. |
| `CellLifecycle` | Runtime-aware dispose/observe/unobserve dispatch. It may remain outside kernel because it takes `Runtime`. |
| Pull verifier | A concrete internal state machine, not a trait. It owns freshness, dependency walk, child verification, cycle detection, and frame cleanup. |
| Push propagator | A concrete internal state machine, not a trait. It owns source-to-subscriber traversal, level-ordered eager recompute, effect execution, and early cutoff. |
| Runtime observer | Runtime-owned observation hook. It receives family-specific concrete event data after safe transitions. It cannot influence scheduling. |
| Public event API | Optional observation surface over concrete `RuntimeEvent` data. It must be append-only where possible and never expose mutable runtime state. |
| Build/language code | Owns domain analysis facades and diagnostics. It reads cells; it does not participate in kernel scheduling. |

## Breaking naming decision

If this ideal design is accepted, rename narrow memo-commit vocabulary before it
spreads further:

- internal `MemoCommitPhase` should not become the top-level name. It can either
  become a private pull-specific helper, or be replaced by a runtime-level event
  sink that carries pull and push event variants;
- public `MemoEvent` / `Runtime::on_memo_event`, if kept, should become a
  runtime-level observation API such as `RuntimeEvent` /
  `Runtime::set_event_sink`, with pull, push, effect, and fixpoint variants
  added deliberately;
- compatibility adapters may exist during migration, but new docs and examples
  should use target facade names and evaluation vocabulary.

This deliberately supersedes the narrower memo-event naming if the project is
ready to break consumers. The behavioral rule is more important than the exact
name: observers see committed facts, never mutable rebuild internals.

## Proposed internal vocabulary

The following sketches are internal shapes. They are not public API promises.

### Freshness

Freshness decides whether the cached value can be reused without recomputing.
The decision must make durability shortcuts and accumulator exceptions explicit.

```moonbit
pub(all) enum FreshnessDecision {
  ReuseWithoutScan
  ScanDependencies
  RebuildNow
}
```

Do not create a public `FreshnessOracle` trait. There is one runtime freshness
algorithm. It should be a helper module or concrete struct used by the pull
verifier.

### Dependency freshness

Dependency classification should distinguish ordinary dirty deps, child deps
that need deep verification, disposed deps, and cycle paths.

```moonbit
pub(all) enum DependencyFreshness {
  Clean
  Dirty
  NeedsChildVerify(CellId)
  Disposed(CellId)
  Cycle(Array[CellId])
}
```

This makes the current broad loop easier to audit. It also prevents disposed
state and cycle state from being hidden behind a boolean "changed" result.

### Pull rebuild summary

A rebuild summary is stable observation data. It should describe what happened,
not how the runtime should continue.

```moonbit
pub(all) enum PullRebuildDisposition {
  Reused
  RecomputedChanged
  RecomputedBackdated
  Aborted
}

pub(all) struct PullRebuildSummary {
  cell_id : CellId
  disposition : PullRebuildDisposition
  dependency_count_before : Int
  dependency_count_after : Int
  changed_at_before : Revision
  changed_at_after : Revision
  verified_at : Revision
  had_synthetic_accumulator_reads : Bool
}
```

The summary should be created only after dependency lists, typed caches,
`verified_at`, `changed_at`, subscriber links, and runtime phase state are safe
for observation.

### Push propagation summaries

Push evaluation is not pull rebuild. It is level-ordered propagation from
changed sources through eager nodes and effects. Its event data should say that,
instead of squeezing it into `PullRebuildSummary`.

Keep queue processing separate from node evaluation. A stale queue entry is not
an eager recompute, so it should not be reported with dependency counts or
`changed_at` fields.

```moonbit
pub(all) enum PushEvaluationKind {
  EagerDerived
  Effect
}

pub(all) enum PushEvaluationDisposition {
  RecomputedChanged
  RecomputedUnchanged
  EffectExecuted
}

pub(all) struct PushEvaluationSummary {
  cell_id : CellId
  kind : PushEvaluationKind
  disposition : PushEvaluationDisposition
  level_before : Int
  level_after : Int
  dependency_count_before : Int
  dependency_count_after : Int
  changed_at_before : Revision
  changed_at_after : Revision
}

pub(all) struct PushEvaluationAbortSummary {
  cell_id : CellId
  kind : PushEvaluationKind
  level : Int
  dependency_count_before : Int
  changed_at_before : Revision
  error : String
}

pub(all) struct PushQueueSkipSummary {
  cell_id : CellId
  queued_level : Int
  current_level : Int
}
```

A propagation pass may also emit a coarser pass summary if a visualizer or
profiler needs totals:

```moonbit
pub(all) struct PushPropagationSummary {
  changed_source_count : Int
  eager_evaluation_count : Int
  effect_execution_count : Int
  skipped_stale_queue_entries : Int
}
```

### Runtime evaluation observer

For the ideal design, the top-level observer should be runtime-wide and carry a
concrete event enum. Pull-specific helpers may still exist internally, but they
are not the public or architectural boundary.

```moonbit
pub(all) enum RuntimeEvaluationEvent {
  PullRebuild(PullRebuildSummary)
  PullRebuildAborted(CellId, String)
  PushEvaluation(PushEvaluationSummary)
  PushEvaluationAborted(PushEvaluationAbortSummary)
  PushQueueSkipped(PushQueueSkipSummary)
  PushPropagationCompleted(PushPropagationSummary)
  FixpointCompleted(FixpointSummary)
}

priv trait RuntimeEvaluationObserver {
  fn on_runtime_evaluation_event(Self, Runtime, RuntimeEvaluationEvent) -> Unit
}
```

Layering rule: an observer trait whose methods take `Runtime` belongs in
`cells/`, like today's `MemoCommitPhase` and `CellLifecycle`. The kernel cannot
import `cells/`, so kernel code should either return concrete event data, push
it into a `RuntimeCore`-owned buffer, or call a kernel-local callback that does
not mention `Runtime`. User callbacks must still drain from the `cells/` facade
after typed caches, phase state, and dependency lists are safe.

`FixpointSummary` is intentionally only named here; its fields should be designed
with the Datalog/fixpoint code when that event family is implemented. The key
rule is that each execution mode gets its own payload, and the umbrella observer
only multiplexes safe committed facts.

## Pull verification as a state machine

The ideal `pull_verify` implementation should read as these transitions:

1. **Enter read.** Validate the target cell, runtime phase, and disposed state.
2. **Revision fast path.** Reuse if `verified_at >= current_revision`.
3. **Freshness shortcut.** Decide whether durability permits skipping the dep
   walk. This transition must be disabled when synthetic accumulator reads exist.
4. **Dependency scan.** Classify each dependency as clean, dirty,
   needs-child-verify, disposed, or cycle.
5. **Child verification.** Push child frames through one centralized path that
   sets `in_progress` and constructs cycle paths.
6. **Recompute.** Run the compute closure under a fresh tracking frame.
7. **Commit.** Diff dependencies, update subscriber links, update typed cache,
   compute durability, set `changed_at`, set `verified_at`, and emit safe
   observer data.
8. **Abort cleanup.** Clear `in_progress`, restore stack/phase invariants, and
   emit an abort event only after the runtime is internally consistent.
9. **Parent propagation.** Propagate child `changed_at` to the parent frame after
   the child result is settled.

The code may use a loop for performance, but the named helpers should preserve
this conceptual order.

## Push propagation as a state machine

The ideal `push_propagate_from` implementation should be equally explicit, but
with push-specific transitions:

1. **Enter propagation.** Enter `PushPropagating` phase and initialize a
   level-ordered queue.
2. **Reachability gate.** Skip a changed source when `push_reachable_count == 0`.
3. **Subscriber discovery.** Traverse through pull and reachable-derived nodes
   only far enough to find downstream eager nodes/effects.
4. **Mark dirty.** Mark each reachable eager/effect node once and enqueue it at
   its current level.
5. **Dequeue by level.** Skip stale queue entries when a node's level changed
   after enqueue.
6. **Evaluate eager node.** Run the compute closure under tracking, diff
   dependencies, update subscriber links, update level, stamp `changed_at` only
   when the cached value changed, and enqueue downstream push subscribers only
   on change.
7. **Execute effect node.** Run the effect under tracking, diff dependencies,
   and update level. Effect execution is a terminal event, not a value rebuild.
8. **Abort cleanup.** If an eager compute or effect execution raises, restore the
   runtime phase, discard transient tracking state, preserve the previously
   committed dependency list, and report `PushEvaluationAborted`. The previous
   value/effect dependency set remains the last committed state; a later retry
   policy must be explicit rather than an accident of a half-updated dirty flag.
9. **Propagate level change.** Recalculate downstream levels when an eager/effect
   source set changes.
10. **Leave propagation.** Restore runtime phase and emit pass-level observation
    only after all dirty nodes are settled.

This state machine shares dependency tracking and subscriber-diff helpers with
pull rebuild, but it must not share pull freshness or backdating vocabulary. A
push abort test should assert that `PushPropagating` is cleared and that stale
tracking frames do not pollute the next recompute.

## Accumulator dependency rule

Synthetic accumulator dependencies are the pressure case that justifies naming
freshness helpers.

A normal dependency can often be skipped by durability or checked by
`CellOps::dep_changed_since`. A synthetic accumulator dependency must also
consider accumulator-slot disposal, target-cell disposal, cycles involving the
target, and `push_revised_at` advancing past the revision recorded by the memo.

Therefore:

```text
Durability shortcut is valid only when the memo has no synthetic accumulator
reads recorded for the cached value being verified.
```

Make this a helper boundary, for example
`can_skip_dep_walk_by_durability(memo)`, so a cleanup cannot accidentally hide
the exception inside a broad boolean expression.

## Reachability and protected-cell invariant

`Watch` roots are now a downstream contract, not just an ergonomic read handle.
Canopy's `ProtectedCell::from_derived` creates a `Watch`, primes it once, and
then the workspace coordinator checks that the protected cell has a GC root.

The runtime must preserve these invariants:

- `watch()` increments root count before a protected cell can be registered;
- `Watch::dispose()` removes the root exactly once;
- `gc()` traverses the latest committed dependency list via `gc_dependencies()`;
- a successful recompute updates `gc_dependencies()` before observers can read
  the rebuild summary;
- disposing an attached scope cannot leave a watched terminal cell with dangling
  upstream dependency references.

Any internal rebuild refactor must run tests that exercise scoped parser
attachments, `Runtime::gc()`, and protected-cell destroy/read behavior.

## Dynamic dependency invariant

Dynamic dependency replacement must be explicit in commit:

- collect new deps in the active tracking frame;
- compare old and new deps;
- update subscriber/reverse links only after the compute result is known;
- publish the new dependency list before GC or observers can see the committed
  value;
- if compute aborts, preserve the previous committed dependency list and clear
  transient frame state.

This is the path used by typecheck chains, parser-attached analysis, and future
request-planning cells. Treat it as the default case.

## Sealed strategy layer

The ideal refactor introduces exchangeable algorithms internally before any
public pluggability. The strategy layer is **sealed**: only in-tree strategies
can touch the fixed store/trace contract.

Fixed contract:

- `RuntimeCore`, `PullState`, `PushState`, and `DatalogState` layout;
- `CellId` identity and cross-runtime checks;
- dependency arrays and subscriber links;
- `changed_at`, `verified_at`, and durability semantics;
- accumulator synthetic dependency semantics;
- `push_reachable_count`, push levels, and dirty flags;
- `Watch` / GC root behavior;
- batch atomicity and phase cleanup;
- buffered event delivery after safe commit points.

Exchangeable internal strategies:

- pull rebuilder: current demand DFS verifier, future work-queue verifier,
  conservative verifier, tracing wrapper;
- push scheduler: current level queue, future allocation-reusing queue,
  deadline/profile-aware in-tree scheduler;
- GC strategy: current mark/sweep, future incremental or profile-guided sweep;
- instrumentation strategy: no-op, buffered event sink, visualizer/profiler
  sink.

The first representation should be a fixed-type internal function record or
private trait whose methods mention concrete `incr` state types. Do not use
associated-type-shaped abstractions; MoonBit cannot express them and the store
contract is intentionally fixed.

## Strategy laws

Every internal scheduler/rebuilder strategy must satisfy the same laws:

1. It never reports a cell fresh unless the fixed trace contract proves it.
2. It never mutates typed caches, dependency arrays, subscribers, revisions, or
   phase flags except through the shared commit/abort helpers.
3. It leaves `RuntimeCore.phase` and tracking stack consistent on every normal,
   cycle, and raised-error exit.
4. It preserves the previous committed dependency list on abort.
5. It emits only buffered event data until state is safe for user callbacks.
6. It preserves `Watch` / GC-root reachability for committed dependencies.
7. It is behaviorally equivalent to the default strategy under the conformance
   test suite, except for documented event ordering or performance counters.

## Public pluggability runway

Public pluggability is possible only after the sealed layer has multiple
in-tree strategies and shared laws. The safe progression is:

1. **Internal sealed strategies.** No public API; `Runtime` selects default
   strategies internally.
2. **Public profile selection.** Expose coarse intent such as
   `RuntimeProfile::InteractiveEditor`, `BatchBuild`, `MemoryTight`, or
   `TraceHeavy`. Profiles map to in-tree strategy bundles.
3. **Opaque scheduler policy.** If needed, expose a validated policy that can
   choose among ready work items through an opaque context. The runtime rejects
   disposed, cross-runtime, or not-ready choices and owns all mutation.
4. **Advisory rebuilder policy.** Rebuilder plugins may request deeper
   verification or force recompute, but the core must re-check any "fresh" or
   "skip" decision before trusting it.
5. **Full public strategy SPI.** Only after conformance laws, failure semantics,
   and performance overhead are proven. This is explicitly out of scope for the
   first refactor.

This keeps BSaC's algorithm-selection idea while preventing public callers from
violating runtime invariants.

## Adoption plan

### Phase 0 — pin pressure tests

Before refactoring internals, ensure tests cover:

- durability fast path with and without accumulator reads;
- cycle detection through normal dependencies;
- cycle detection through synthetic accumulator dependencies;
- cleanup of `in_progress` after raised compute failures;
- `changed_at` propagation to parent frames;
- dynamic dependency replacement;
- push propagation level ordering and stale queue-entry skips;
- push/effect abort cleanup restoring phase and tracking invariants;
- `Watch`/`Scope` GC survival for parser attachments;
- protected-cell registration/read/destroy behavior in Canopy.

### Phase 1 — replace memo-only observation vocabulary

If breaking changes are acceptable in the target branch, stop treating memo
commit as the top-level event model. Introduce runtime evaluation vocabulary
first, then map the current memo events into the pull event family. Keep
compatibility adapters only if downstream migration needs a short bridge.

### Phase 2 — split pull verification helpers

Extract helpers inside the existing kernel package first:

| Helper | Responsibility |
| --- | --- |
| `memo_is_revision_fresh` | `verified_at >= current_revision` fast path. |
| `can_skip_dep_walk_by_durability` | Durability shortcut, disabled by synthetic accumulator reads. |
| `classify_dependency_freshness` | Wrap dependency changed/disposed/fixpoint/cycle checks. |
| `enter_pull_frame` | Push frame, set `in_progress`, build cycle path if needed. |
| `run_pull_recompute` | Execute compute under tracking, collect deps, capture abort. |
| `commit_pull_rebuild` | Diff deps, write cache, stamp revisions, publish observer summary. |
| `abort_pull_rebuild` | Restore invariants and emit abort observation. |

### Phase 3 — split push propagation helpers

After pull verification has named transitions, apply the same discipline to
`push_propagate_from`:

| Helper | Responsibility |
| --- | --- |
| `enqueue_reachable_push_subscribers` | Reachability-gated BFS from changed sources to eager/effect nodes. |
| `dequeue_push_evaluation` | Level-ordered pop with stale-entry detection and queue-skip event construction. |
| `evaluate_push_reactive` | Run eager compute, diff deps, update level, stamp `changed_at`, report summary. |
| `execute_push_effect` | Run effect, diff deps, update level, report summary. |
| `abort_push_evaluation` | Restore phase/tracking invariants, preserve committed deps, report abort summary. |
| `propagate_push_level_change` | Recalculate downstream levels and requeue dirty nodes. |
| `finish_push_propagation` | Leave phase and emit pass summary after state is settled. |

### Phase 4 — introduce sealed strategy bundles

After helpers establish shared commit/abort boundaries, wrap the default
algorithms in an internal strategy bundle. The first bundle should point at the
current implementations so behavior and `.mbti` shape stay stable.

The strategy methods should use fixed concrete state types and should not take
user callbacks. The runtime may store a strategy bundle internally, but external
callers should still construct a default `Runtime`.

### Phase 5 — add in-tree alternate strategies behind tests

Add at least one non-default in-tree strategy before considering public profile
selection. Good first alternates are tracing wrappers or conservative strategies
that deliberately recompute more often but should produce identical values.

Each alternate must run the same conformance tests as the default strategy:
cycles, accumulator synthetic deps, dynamic deps, push levels, abort cleanup,
GC roots, batch rollback, and downstream loom/Canopy pressure tests.

### Phase 6 — expose public profiles only after sealed strategies settle

Once multiple in-tree strategies pass the shared laws, expose coarse profile
selection if there is a real consumer need:

```moonbit
pub(all) enum RuntimeProfile {
  Default
  InteractiveEditor
  BatchBuild
  MemoryTight
  TraceHeavy
}
```

Profiles map to in-tree strategy bundles. They do not expose `RuntimeCore`,
trace storage, or scheduler/rebuilder internals.

### Phase 7 — expose public observation only when needed

Expose public runtime events only when a real driver needs them for tracing,
progress, visualization, or profiling. The API should be observation-only:

```moonbit
pub(all) enum RuntimeEvent {
  PullRebuild(PullRebuildSummary)
  PullRebuildAborted(CellId, String)
  PushEvaluation(PushEvaluationSummary)
  PushEvaluationAborted(PushEvaluationAbortSummary)
  PushQueueSkipped(PushQueueSkipSummary)
  PushPropagationCompleted(PushPropagationSummary)
}

pub(open) trait RuntimeEventSink {
  fn on_runtime_event(Self, RuntimeEvent) -> Unit
}
```

The event payload must remain concrete data. It must not expose mutable runtime
state or allow the sink to influence scheduling. Datalog/fixpoint variants
should be added only with mode-specific payloads.

## Validation for implementation PRs

Run the local `incr` suite:

```bash
moon fmt
moon info
moon check
moon test
```

For downstream pressure, also run from the containing repositories when the
submodule pointer is updated:

```bash
# from the dowdiness/loom repository root
cd examples/lambda && moon test

# from the dowdiness/canopy repository root
moon test ffi/lambda
```

Use the parent repositories' CI commands if paths differ. The important
requirement is that parser-attached lambda analysis and protected-cell lifecycle
tests run against the changed `incr`.

## Non-goals

- No public scheduler, rebuilder, or freshness oracle in the first strategy
  refactor.
- No user-provided rebuild strategy until internal strategies, laws, and opaque
  contexts prove the boundary safe.
- No split of `RuntimeCore` into service objects without a separate driver.
- No language/build-stage traits in `incr` root.
- No network or async execution in recompute closures.
- No performance optimization without fresh benchmarks.

## Done criteria

- Pull verification reads as named freshness, dependency scan, child verify,
  recompute, commit, abort cleanup, and parent propagation transitions.
- Push propagation reads as named reachability gate, enqueue, queue skip,
  level-ordered evaluation, eager recompute, effect execution, abort cleanup,
  level propagation, and finish transitions.
- Observation vocabulary is runtime-wide, with pull and push represented by
  separate payloads rather than one overloaded rebuild event.
- The default algorithms can be selected through an internal sealed strategy
  bundle without changing public behavior.
- Any future public profile or plugin surface is backed by conformance tests and
  keeps store/trace internals opaque.
- `Watch`, `Scope`, GC, dynamic dependency, accumulator, cycle, and abort tests
  pass.
- Downstream loom lambda analysis and Canopy protected-cell tests pass after any
  submodule pointer update.
- Any `.mbti` diff is intentional and explained.
