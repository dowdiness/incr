# Evaluation Strategy Refactor Plan

**Status:** Proposed

**Date:** 2026-05-26

**Related specs:**

- [Internal Evaluation Boundaries](../design/specs/2026-05-26-internal-rebuild-boundaries.md)
- [Build-Oriented Boundary Design](../design/specs/2026-05-26-build-trait-boundaries.md)

## Goal

Refactor `incr` toward a Build Systems à la Carte-inspired internal structure:
keep store and trace representation fixed, but make scheduler and rebuilder
algorithms internally selectable through sealed strategy bundles.

The first implementation must preserve public behavior. Public pluggability is a
later possibility, not a requirement for this plan.

## Design stance

BSaC separates task meaning, store, scheduler, and rebuilder. In `incr`:

- tasks are installed cell compute closures;
- store is `RuntimeCore` plus pull/push/datalog state and typed wrapper caches;
- trace is dependencies, subscriber links, revisions, durability, accumulator
  synthetic reads, and push levels;
- rebuilder is pull verification;
- scheduler is demand pull traversal, level-ordered push propagation, batch
  commit, and fixpoint iteration.

This refactor makes those seams visible without exposing `RuntimeCore`,
`PullState`, `PushState`, or trace mutation to users.

## Non-goals

- No public scheduler or rebuilder plugin in this plan.
- No user-provided freshness oracle.
- No change to public target facades unless a later profile API is explicitly
  accepted.
- No change to store/trace representation as part of strategy extraction.
- No async, network, or provider execution inside compute closures.
- No performance optimization without fresh benchmarks.

## Constraints

- MoonBit traits have no associated types. Strategy interfaces must use fixed
  concrete state types or function records.
- Kernel packages cannot import `cells/` types that mention `Runtime`. Any
  observer trait that takes `Runtime` lives in `cells/`; kernel code returns or
  buffers concrete event data.
- Existing `Watch`, `Scope`, GC, accumulator, dynamic dependency, batch, and
  cycle semantics are part of the conformance contract.
- Generated `.mbti` diffs are not expected before the optional public profile
  phase.

## Phase 0 — conformance inventory

Pin behavior before structural changes.

Required local tests or identified existing tests:

- pull durability fast path with and without accumulator reads;
- cycle detection through ordinary dependencies;
- cycle detection through synthetic accumulator dependencies;
- compute failure cleanup of `in_progress` and tracking stack;
- dynamic dependency replacement;
- backdating and `changed_at` propagation;
- push diamond glitch prevention;
- push stale queue-entry skip behavior;
- push/effect failure cleanup of `RuntimeCore.phase` and tracking stack;
- batch rollback;
- `Watch` / `Scope` GC survival;
- Datalog fixpoint no-regression smoke tests.

### Initial inventory

Status legend: **covered** means an existing local test directly pins the
invariant; **partial** means existing tests cover adjacent behavior but leave a
listed subcondition unpinned; **gap** means no direct local test was found during
Phase 0 discovery.

| Required invariant | Existing anchors | Status / next action |
| --- | --- | --- |
| Pull durability fast path with and without accumulator reads | `cells/durability_wbtest.mbt` (`durability: high-only memo skips verify when low input changes`, `durability: shortcut boundary — High memo stays skipped when durability_last_changed[High] equals verified_at`); `cells/accumulator_wbtest.mbt` (`durability shortcut: bypassed when memo has accumulator_reads`, `synthetic dep check: reader invalidates when producer's push_revised_at bumps`, `verify: non-root frame checks accumulator_reads`) | **Covered.** Normal durability shortcuts and the accumulator-read exception are both pinned. |
| Cycle detection through ordinary dependencies | `cells/verify_path_test.mbt`; `cells/cycle_path_test.mbt`; `cells/cycle_test.mbt`; `cells/reachable_derived_wbtest.mbt` (`panic hybrid cycle: mixed Memo → HybridMemo → Memo cycle aborts`) | **Covered.** Ordinary pull cycles, self-cycles, path formatting, re-verification cycles, and mixed Memo/Hybrid cycles are pinned. |
| Cycle detection through synthetic accumulator dependencies | `cells/accumulator_wbtest.mbt` (`verify: synthetic accumulator dep surfaces target cycle and cleans up`, plus synthetic dependency recording/invalidation tests) | **Covered.** Synthetic accumulator verification reaches a cyclic target, returns a `CycleError`, and clears in-progress/tracking state. |
| Compute failure cleanup of `in_progress` and tracking stack | `cells/accumulator_wbtest.mbt` (`verify: raise-path from compute does not leak in_progress on ancestors`); `cells/accumulator_commit_hook_wbtest.mbt` (`MemoCommitPhase: forward dispatch order on abort`, `MemoCommitPhase: nested recompute aborts clean up both entries`); `cells/event_broadcast_hook_wbtest.mbt` (`memo_event: hook order on abort removes active entries before later hooks`); `cells/verify_wbtest.mbt` leak simulations | **Covered.** Raised compute cleanup directly asserts empty tracking stack and false `in_progress` flags, with hook cleanup pinned separately. |
| Dynamic dependency replacement | `tests/integration_test.mbt` (`integration: dynamic dependencies`); `cells/derived_dep_diff_wbtest.mbt` (`dep diff: dynamic deps update dep list and durability`); `cells/subscriber_link_wbtest.mbt` (`subscriber: dynamic dep changes update subscriber links`); `tests/subscriber_test.mbt` (`subscriber: dynamic deps update dependents via public API`) | **Covered.** Value behavior, dependency lists, durability recomputation, and subscriber links are pinned. |
| Backdating and `changed_at` propagation | `cells/backdating_test.mbt`; `cells/introspection_test.mbt` (`memo: changed_at and verified_at track revisions`); `cells/target_facade_wbtest.mbt` (`Derived::changed_at forwards to inner Memo`); `cells/reachable_derived_wbtest.mbt` (`hybrid memo: backdating — unchanged value does not bump changed_at`); `tests/backdate_eq_test.mbt` | **Covered.** Pull backdating, explicit `changed_at` movement, facade forwarding, and custom equality behavior are pinned. |
| Push diamond glitch prevention | `cells/eager_derived_wbtest.mbt` (`push propagation: glitch prevention in diamond`); related pull diamond smoke in `tests/integration_test.mbt` (`integration: diamond dependency`, `integration: diamond with backdating`) | **Covered.** Push diamond consistency is directly pinned. |
| Push stale queue-entry skip behavior | `cells/eager_derived_wbtest.mbt` (`push propagation: skip stale queue entry after mid-wave disposal`) | **Covered.** Stale queued push node disposal is directly pinned. |
| Push/effect failure cleanup of `RuntimeCore.phase` and tracking stack | `cells/eager_derived_wbtest.mbt` (`push abort: reactive failure restores phase stack and sources`, `push abort: effect failure restores phase stack and sources`) uses a wbtest-only push-frame harness because current public push closures are non-raising; `cells/phase_wbtest.mbt` covers normal phase enter/leave; `cells/event_broadcast_hook_wbtest.mbt` (`memo_event: mutation guard rejects push tracking frame`) confirms push tracking frames are observable to guards. | **Covered by harness.** The cleanup shape restores `Idle`, clears tracking/global runtime state, and preserves the last committed source list without introducing internal `.mbti` API drift in Phase 0. |
| Batch rollback | `cells/batch_wbtest.mbt` (`batch: raised error rolls back pending writes and restores depth`, `batch: nested raised error rolls back entire outer batch`, `batch: failed inner batch_result rolls back before outer continues`, `batch_result: returns Err and rolls back`); `tests/traits_test.mbt` (`trait: batch via Database rolls back on raised error`); `tests/scope_test.mbt` (`scope: dispose during batch — pending signal writes discarded`) | **Covered.** Local and public-facade rollback paths are pinned. |
| `Watch` / `Scope` GC survival | `tests/target_facade_test.mbt` (`facade derived: watch reads outside graph and keeps target alive`, `facade reachable derived: watch reads outside graph`, `facade eager derived: watch reads outside graph`, `facade scope: add_watch disposes target watch`); `tests/gc_test.mbt`; `cells/gc_wbtest.mbt`; `tests/scope_test.mbt`; `cells/scope_test.mbt`; `cells/target_facade_wbtest.mbt` (`facade scope: target handles are disposed with scope`) | **Covered.** Watch roots, GC root counts, scope disposal ordering, and watched target survival across `gc()` are pinned. |
| Datalog fixpoint no-regression smoke tests | `cells/datalog_wbtest.mbt` (`fixpoint: transitive closure — edge(a,b)+edge(b,c) derives path(a,c)`, `fixpoint: semi-naive recursion preserves delta frontier across iterations`, `fixpoint: terminates when no new facts derived`, `fixpoint: relation created during rule execution converges in same call`, `fixpoint: push Reactive downstream of Relation recomputes before on_change`); `cells/datalog_map_relation_wbtest.mbt`; `tests/integration_test.mbt` (`cross-engine: fixpoint fires on_change only when facts change`) | **Covered.** Relation, map-relation, convergence, pull invalidation, and push/on-change interaction smoke paths are pinned. |

Downstream pressure tests before changing submodule pointers:

```bash
# from dowdiness/loom
cd examples/lambda && moon test

# from dowdiness/canopy
moon test ffi/lambda
```

Deliverable: a checklist in the implementation PR that maps each invariant to a
test file.

## Phase 1 — helper extraction without strategy indirection

Split the current algorithms into named helpers while keeping call sites and
behavior unchanged.

Pull verification helpers:

- `memo_is_revision_fresh`
- `can_skip_dep_walk_by_durability`
- `classify_dependency_freshness`
- `enter_pull_frame`
- `run_pull_recompute`
- `commit_pull_rebuild`
- `abort_pull_rebuild`

Push propagation helpers:

- `enqueue_reachable_push_subscribers`
- `dequeue_push_evaluation`
- `evaluate_push_reactive`
- `execute_push_effect`
- `abort_push_evaluation`
- `propagate_push_level_change`
- `finish_push_propagation`

Validation:

```bash
moon check
moon test
```

Expected public API change: none.

## Phase 2 — concrete event data, still internal

Introduce internal summary data for pull and push transitions. Keep user
callbacks buffered and drained from the `cells/` facade after safe state points.

Event families:

- pull rebuild summary and abort summary;
- push evaluation summary and abort summary;
- push queue-skip summary;
- push propagation pass summary.

Do not expose a public event API in this phase. Existing memo-event compatibility
can remain until a deliberate migration PR replaces it.

Validation:

```bash
moon check
moon test cells/event_broadcast_hook_wbtest.mbt
moon test cells/accumulator_commit_hook_wbtest.mbt
```

Expected public API change: none, unless the PR deliberately renames the existing
memo-event API.

## Phase 3 — sealed internal strategy bundle

Wrap the default algorithms in an internal strategy bundle. The first bundle
points to the current behavior.

Candidate shape, illustrative only:

```moonbit
// In an internal package or kernel-owned file; exact syntax belongs to the PR.
struct EvaluationStrategies {
  pull_rebuilder : PullRebuilderStrategy
  push_scheduler : PushSchedulerStrategy
}
```

Strategy methods must mention concrete state types and call shared commit/abort
helpers. They must not own store mutation directly.

Deliverables:

- `Runtime` construction installs the default strategy bundle internally;
- existing read/set/batch/fixpoint call sites route through the bundle where
  appropriate;
- no public constructor changes.

Validation:

```bash
moon fmt
moon info
moon check
moon test
git diff '**/pkg.generated.mbti'
```

Expected public API change: none.

## Phase 4 — first alternate in-tree strategy

Add one alternate strategy to prove the seam is real. Prefer a behaviorally
conservative option:

- a tracing wrapper that records summaries while delegating to the default; or
- a conservative pull rebuilder that recomputes more often but never returns
  stale values; or
- a push scheduler wrapper that collects queue/evaluation counters.

The alternate must run the same conformance tests as the default. If the test
harness cannot run both strategies, build that harness before adding more
strategies.

Validation:

```bash
moon test
moon bench --release   # only if the alternate is performance-relevant
```

Expected public API change: none.

## Phase 5 — optional public profile API

Only after multiple in-tree strategies pass conformance, consider a coarse
profile API:

```moonbit
pub(all) enum RuntimeProfile {
  Default
  InteractiveEditor
  BatchBuild
  MemoryTight
  TraceHeavy
}
```

Profiles select in-tree strategy bundles. They do not expose algorithm names,
store internals, or trace mutation.

Acceptance for this phase:

- profile names correspond to measured or tested use cases;
- default profile exactly preserves current behavior;
- `.mbti` diff is intentional and documented;
- docs and examples show profile selection as optional.

## Phase 6 — public pluggability research gate

Do not implement public plugins until all conditions hold:

1. At least two in-tree strategies exist per exposed axis.
2. Strategy laws are documented and enforced by shared tests.
3. Scheduler plugins receive only opaque ready-work contexts.
4. Rebuilder plugins are advisory unless the core can independently validate
   every fresh/skip decision.
5. Plugin callbacks never run while runtime state is half-committed.
6. Benchmark overhead is measured.

This phase should start as a research document or ADR, not as an implementation
PR.

## Acceptance criteria for the first refactor PR

- Pull and push algorithms are split into named helpers.
- Default behavior is unchanged.
- No public `.mbti` changes unless explicitly accepted.
- Local `moon check` and `moon test` pass.
- The implementation PR lists which tests cover each strategy law.
- Downstream loom lambda and Canopy lambda FFI pressure tests are run before any
  submodule pointer update.
