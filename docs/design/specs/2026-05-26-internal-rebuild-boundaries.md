# Internal Rebuild Boundaries

**Status:** Proposed

**Date:** 2026-05-26

**Related:** [Build-oriented trait boundaries](2026-05-26-build-trait-boundaries.md)

## Goal

Improve `incr`'s internal structure by naming the scheduler/rebuilder seams that
already exist in the runtime, while preserving the public API and the current
single-runtime execution model.

This is not a proposal for public pluggable scheduling. It is an internal
refactoring guide for making the pull verification path, rebuild hooks, and
cross-engine guards easier to reason about.

## Scope clarification

This document is about `incr`'s runtime internals: freshness checks, dependency
tracking, rebuild hooks, and verification invariants. It does not define
application pipeline traits such as `Source`, `Parser`, `Checker`, or
`Transformer`; those belong to the companion
[build-oriented trait proposal](2026-05-26-build-trait-boundaries.md).

The two proposals are intentionally asymmetric:

- application build traits stay local to consumers because their key, diagnostic,
  syntax, and artifact types are domain-specific;
- internal rebuild boundaries stay inside `incr` because they protect runtime
  invariants shared by every consumer.

## Motivation

The current package split already keeps storage, graph algorithms, and public
facades separate. The remaining pressure is inside the rebuild path itself:
`pull_verify` must decide freshness, walk dependencies, detect cycles, handle
synthetic accumulator dependencies, run recompute closures, clear `in_progress`
flags on every exit path, and propagate `changed_at` to parent frames. Those
responsibilities are correct but hard to audit when they are all expressed in one
loop.

This matters because the bugs are invariant bugs, not ordinary type errors. A
missed `in_progress` cleanup can poison future reads. A misplaced durability
shortcut can ignore accumulator invalidation. A callback fired before typed cache
writeback can expose stale values. Naming the internal seams makes those failure
modes visible without changing the public API.

The design also draws a line between two kinds of extensibility:

- **Internal extension points** for runtime-owned concepts that already have more
  than one implementation or observer, such as `CellOps` and `MemoCommitPhase`.
- **Deferred abstractions** for concepts with only one algorithm today, such as
  pull verification and push propagation. These should become named helpers
  first, not public traits.

## Current responsibility map

`incr` already has a good package split. The improvement target is not another
large package decomposition; it is clearer internal boundaries inside the
existing `cells/` and `cells/internal/kernel/` layers.

| Existing area | Current responsibility | Structural pressure |
|---|---|---|
| `Runtime` in `cells/runtime.mbt` | Owns public handle state, accumulator/event hook state, and thin delegators into kernel algorithms. | Must keep some arrays outside kernel because traits such as `CellLifecycle` and `MemoCommitPhase` mention `Runtime`. |
| `RuntimeCore` in `cells/internal/kernel/state.mbt` | Pure kernel-owned coordinator state: revision, tracking stack, batch state, cell index, dispatch tables, phase, GC roots. | It is the right state owner; avoid splitting it into public services without a real driver. |
| `CellOps` in `cells/internal/shared/cell_ops.mbt` | Object-safe metadata and dependency-graph operations over all cell kinds. | Good existing trait boundary; keep it fixed-type and internal. |
| `CellLifecycle` in `cells/cell_ops.mbt` | Runtime-aware lifecycle dispatch for dispose/observe/unobserve. | Correctly lives in `cells/` because it takes `Runtime`. |
| `Tracker` / `RevisionManager` in `cells/cell_ops.mbt` | Organizational traits grouping concrete `Runtime` methods. | Useful precedent for internal capability naming without public polymorphism. |
| `MemoCommitPhase` in `cells/memo_commit_phase.mbt` | Ordered hooks around pull memo recompute. | The name is narrower than the concept; future tracing/progress wants a rebuild-observation seam. |
| `pull_verify` in `cells/internal/kernel/verify.mbt` | Freshness check, dependency walk, cycle detection, synthetic accumulator-dep check, and recompute triggering. | It is the highest-value place to split concepts, but only after preserving behavior with whitebox tests. |
| `propagate`, `push_propagate`, `batch`, `gc`, `fixpoint` kernel files | Concrete algorithms for the existing execution modes. | Keep algorithms concrete until a second implementation exists. |

## Design rules

1. **No public scheduler trait.** A public `Scheduler` or `Rebuilder` would need
   associated types for key, value, task, and store. MoonBit cannot express that
   directly, and exposing it would let callers violate runtime invariants.
2. **Use concrete internal capability traits only where there is dispatch.** If
   there is one implementation, prefer helper functions and records. Add a trait
   when the runtime stores trait objects or when a capability has multiple
   implementations.
3. **Keep traits object-safe when they are stored.** Methods on stored trait
   objects must take `Self` only as the first parameter and should return
   concrete types, not `Self`.
4. **Keep user callbacks out of recompute internals.** Internal hooks may buffer
   events, but user code should run only after typed caches and runtime phase
   state are safe.
5. **Preserve `.mbti` shape.** This refactor should not change the root facade,
   target handles, or compatibility APIs.

## Compatibility and extension policy

This proposal reserves vocabulary before it reserves API surface. A name such as
`FreshnessDecision` or `PullRebuildSummary` is safe when it helps describe an
existing invariant. A trait is not safe until the runtime needs polymorphic
dispatch or multiple concrete implementors.

Apply these rules when the internals evolve:

- Prefer private helper functions for a single algorithm.
- Prefer concrete result data when a future observer may need stable event
  payloads.
- Prefer a private trait only when the runtime stores trait objects or when two
  independent hooks share the same callback surface.
- Do not add public types until an external use case needs observation rather
  than control.
- When a public event type is eventually added, make it append-only where
  possible. New event variants are less disruptive than changing existing fields
  or method signatures.

The intended compatibility story is therefore conservative: internal names may
move while the proposal is experimental; root `incr` users should see no API
change. Public observation, if added later, should be introduced as a separate
feature with its own ADR.

## Proposed internal vocabulary

These names are for internal concepts. They do not imply immediate new public
APIs.

### Freshness

Freshness answers whether a cached node can be reused at the current revision.
Today this logic is embedded in `pull_verify` and `CellOps::dep_changed_since`.

Useful fixed-type concepts:

```moonbit
pub(all) enum FreshnessDecision {
  Fresh
  Stale
  NeedsDeepVerify
}
```

Do not create a public `FreshnessOracle` trait. If the helper has one concrete
implementation, keep it as functions in `cells/internal/kernel/verify.mbt` or a
sibling file.

### Dependency recording

Dependency recording is already represented by `Tracker` and kernel tracking
helpers. Keep that split:

- `cells/internal/kernel/tracking.mbt` owns stack mutation.
- `cells/tracking.mbt` exposes concrete `Runtime` wrappers and implements the
  organizational `Tracker` trait.
- Compute closures should continue to use `Input::get()` and
  `Derived::get_or_abort()` / `DerivedMap::get_or_abort()` so the active frame
  records dependencies.

No new trait is needed here.

### Pull rebuild

Rebuild is the act of running a memo compute closure after freshness says the
cached value is stale. Internally it includes hook dispatch, dependency diff,
backdating, typed-cache writeback by the public wrapper, and event buffering.

The safest near-term improvement is to name the outcome data, not to expose a
pluggable trait:

```moonbit
pub(all) enum PullRebuildDisposition {
  Reused
  Recomputed
  Backdated
}

pub(all) struct PullRebuildSummary {
  cell_id : CellId
  disposition : PullRebuildDisposition
  dependency_count : Int
}
```

Only add a trait if two rebuild observers need the same fixed callback surface.
The current `MemoCommitPhase` already serves this role for accumulator and memo
events.

### Rebuild observation

A future public-facing tracing/progress API should be observation-only. The
internal shape can be stricter than the public one:

```moonbit
priv trait RebuildObserver {
  fn before_rebuild(Self, Runtime, CellId) -> Unit
  fn after_rebuild(Self, Runtime, PullRebuildSummary) -> Unit
  fn after_rebuild_abort(Self, Runtime, CellId, Error) -> Unit
}
```

This is a possible successor name for `MemoCommitPhase`, but it should not be
renamed mechanically until there is a second event family beyond pull memos.
`MemoCommitPhase` is correct for today's implementation.

### Dirty propagation

Push invalidation and subscriber publication are already concrete kernel
algorithms. A trait such as `DirtyPropagator` is not useful until there is a
second propagation strategy. For now, improve names and helper boundaries inside
`propagate.mbt` and `push_propagate.mbt` rather than abstracting them.

## Concrete pressure case: accumulator dependencies

Accumulator reads are the clearest example of why internal rebuild boundaries
need names. A normal dependency can be checked through `CellOps::dep_changed_since`
or deep verification. A synthetic accumulator dependency also has to check
whether the accumulator slot was disposed, whether the target cell was disposed,
whether the target now participates in a cycle, and whether the target's
`push_revised_at` advanced past the revision recorded by the memo.

That special case intentionally disables the durability shortcut. If this rule
is hidden inside a broad verification loop, a future cleanup can accidentally
restore the shortcut and skip a real invalidation. A helper boundary such as
`can_skip_dep_walk_by_durability` makes the exception explicit: durability is a
freshness optimization only when no synthetic accumulator reads exist.

## Adoption recommendation

If this proposal is implemented, start with the smallest readability refactor:
split `pull_verify` into private helpers inside `cells/internal/kernel/verify.mbt`.
Do not introduce `RebuildObserver`, do not rename `MemoCommitPhase`, and do not
add public rebuild events in the same PR. Those are separate decisions that need
a second event family or an external tracing/progress use case.

The first code slice should be judged by auditability, not performance. If a
helper extraction changes benchmark numbers materially, stop and investigate;
this proposal is not an optimization plan.

## Implementation notes

The sections below are not part of the stable design contract. They describe a
safe first implementation path if this proposal is accepted. Keep implementation
PRs small enough that each phase can be reviewed against the invariants above.

### Phase 0 — keep this as a design-only boundary

Record the internal vocabulary and constraints. Do not move code until a
specific pain point is selected.

Validation:

```bash
moon check
git diff --check
```

### Phase 1 — split `pull_verify` by helper responsibility

Before changing behavior, add or identify whitebox tests for:

- durability fast path with and without accumulator reads;
- cycle detection through normal dependencies;
- cycle detection through synthetic accumulator dependencies;
- cleanup of `in_progress` flags after raised compute failures;
- `changed_at` propagation to parent frames.

Then extract helpers inside the same package:

| Helper | Responsibility |
|---|---|
| `memo_is_revision_fresh` | `verified_at >= current_revision` check. |
| `can_skip_dep_walk_by_durability` | Durability shortcut, explicitly disabled when synthetic accumulator reads exist. |
| `classify_dependency_freshness` | Wrap `CellOps::dep_changed_since` plus disposed/fixpoint guards. |
| `push_verify_frame` | Push a memo frame and set `in_progress`, with cycle path construction centralized. |
| `finalize_verify_frame` | Synthetic accumulator check, optional recompute, `verified_at` stamping, parent changed propagation. |

Keep these as functions first. A trait would be premature because there is only
one pull verification algorithm.

### Phase 2 — rename or wrap commit-phase vocabulary only if needed

If another feature needs rebuild lifecycle observation, introduce
`RebuildObserver` as an internal trait and adapt `MemoCommitPhase` deliberately:

- either keep `MemoCommitPhase` and document it as the pull-memo observer;
- or replace it with `RebuildObserver` if the callback payload becomes genuinely
  generic across pull memo, reachable derived, and future task families.

Do not expose user callbacks from this trait. Public observation should remain
buffered through `Runtime::on_memo_event` or a future event API.

### Phase 3 — add public observation only after internal shape settles

A public API may eventually expose rebuild summaries for tracing, progress, or
profiling. It should be observation-only:

```moonbit
pub(open) trait RebuildEventSink {
  fn on_rebuild_event(Self, RebuildEvent) -> Unit
}
```

`RebuildEvent` must be concrete data and must not expose mutable runtime state.
Do not let users choose the scheduler or rebuilder from the public facade.

## Non-goals

- No new public scheduler/rebuilder trait.
- No split of `RuntimeCore` into service objects.
- No replacement of `CellOps`; it is already the right internal object-safe
  metadata trait.
- No language/build-stage traits in the `incr` root package.
- No performance optimization without a fresh benchmark.

## Done criteria for an implementation PR

- Root `pkg.generated.mbti` has no unintended public API changes.
- Existing whitebox tests for pull verification, accumulators, GC, batch, and
  reachability pass.
- `moon check`, `moon test`, `moon fmt`, and `moon info` pass.
- Any `.mbti` diff is explained and intended.
- The refactor leaves `pull_verify` easier to audit: freshness, dependency walk,
  cycle cleanup, synthetic accumulator deps, and recompute finalization are named
  separately.
