# Design — How incr Works Under the Hood

> **Note for users**: If you're new to `incr`, start with the [Getting Started](../getting-started.mbt.md) guide and [Core Concepts](../concepts.mbt.md). This document is for contributors or users who want to understand the implementation deeply.

This document explains the theoretical foundations and implementation details of the `incr` library. For usage and API examples, see [incr/README.mbt.md](../../incr/README.mbt.md). For contributor/AI guidance, see [CLAUDE.md](../../CLAUDE.md).

Naming: this document uses the current facade names — `Input`, `Derived`,
`ReachableDerived`, `DerivedMap`, `EagerDerived`, `InputField`. The legacy
names `Signal`, `Memo`, `HybridMemo`, and `MemoMap` were removed in v0.12.0.
Internal identifiers (`MemoData`, `memo_force_recompute`, `pull.memos`) keep
the word "memo"; that is deliberate — they name the memoization mechanism, not
the removed public type.

## Motivation & Background

### The Recomputation Problem

Many programs model computations as a graph of derived values: some values are inputs, and others are computed from those inputs through intermediate steps. When an input changes, the naive approach recomputes every derived value from scratch. For large graphs this is wasteful — most derived values are unaffected by any single input change.

Incremental computation solves this by tracking which derived values actually depend on which inputs and only recomputing what is necessary.

### Salsa as Inspiration

`incr` borrows its core ideas from [Salsa](https://salsa-rs.github.io/salsa/), the incremental computation framework used by rust-analyzer. The key ideas adapted from Salsa are:

- **Pull-based lazy verification**: derived values are not eagerly recomputed when inputs change. Instead, when a derived value is read, the framework checks whether it is still valid by walking its dependency chain.
- **Automatic dependency tracking**: dependencies are discovered at runtime by intercepting reads, not declared statically.
- **Backdating**: when a derived value is recomputed but produces the same result as before, its change timestamp is preserved, preventing unnecessary downstream recomputation.
- **Durability-based shortcuts**: inputs are classified by how often they change, allowing entire subgraphs of stable inputs to skip verification.

### Push vs. Pull vs. Hybrid

Invalidation strategies for dependency graphs fall into three families:

- **Push-based** (eager): when an input changes, immediately propagate invalidation to all transitive dependents. Simple, but can cause a cascade of wasted work if many intermediate values recompute to the same result.
- **Pull-based** (lazy): do nothing when an input changes. When a derived value is read, walk its dependencies to check if anything changed. This is what `incr` uses — it avoids wasted work at the cost of a verification walk on read.
- **Hybrid**: combine push notifications with pull verification. Salsa itself has evolved toward hybrid approaches in newer versions.

`incr`'s cell types map onto these families as follows:

- **`Input` / `Derived`** — pure pull. `Input::set()` only bumps a revision counter; all verification and recomputation happens lazily when the derived value is read.
- **`EagerDerived` / `Effect`** — push. They recompute eagerly during `Input::set()` / batch-commit propagation.
- **`ReachableDerived`** — pull recomputation with push *reachability*. It participates in `push_reachable_count` so live `EagerDerived`/`Effect` observers downstream keep upstream cells reachable for `gc()`. Recomputation is the same lazy `verified_at < current_revision` check as `Derived`; there is no separate dirty flag. The "hybrid" is reachability, not invalidation.

### Where `incr` Sits in the Design Space

Mokhov, Mitchell, and Peyton Jones (2020) decompose incremental build systems along two orthogonal axes: a **scheduler** (Topological / Restarting / Suspending) and a **rebuilder** (Dirty bit / Verifying traces / Constructive traces / Deep constructive traces). The taxonomy applies cleanly to incremental computation libraries too. `incr` is a **(Suspending, Verifying traces) system with cycle detection added**.

| Axis | `incr`'s choice | What that means |
|---|---|---|
| Scheduler | Suspending | When a derived value is read, the scheduler recursively verifies dependencies on demand. `pull_verify` is the suspending scheduler. |
| Rebuilder | Verifying traces via revisions | `verified_at` / `changed_at` play the role of input/output hashes in the paper's framework. Revisions are cheaper to compare than hashes (single integer, transitively monotonic, no collision risk) but cannot be shared across processes. See the [Constructive traces feasibility study](../research/constructive-traces-feasibility.md) for why constructive traces remain opt-in research rather than the default rebuilder. |
| Task abstraction | Monadic | Compute functions can branch on read values; the dependency graph cannot be predicted ahead of time. Equivalent to Shake or Excel's task model, strictly more general than Selective. |
| Beyond the paper | Recoverable cycles via `CycleError` | The build-systems literature assumes acyclic task graphs. `incr` chooses to report cycles as recoverable errors rather than aborts. This is what motivates `Result[T, ReadError]` as the canonical read return type on derived cells. |

Named correspondences with the paper:

- **Early cutoff** (paper) = **backdating** (`incr`). When a derived cell recomputes to the same value, its `changed_at` is preserved, so dependents see no change and skip verification.
- **Verifying traces** (paper) = the `verified_at`/`changed_at` revision pair plus per-cell deps. The verification predicate `verified_at >= current_revision OR no dep changed_at > my verified_at` is the revision-based analogue of "stored input hash == current input hash."
- **Durability shortcut** (`incr`) has no direct paper analogue. It coarsens the verifying-trace check at the input-class level — if no input of class `D` has changed since this cell was verified, skip the dep walk entirely. Effectively a fast path on top of the Verifying-traces rebuilder.

Comparison to neighboring systems in the same cell:

- **Salsa** (rust-analyzer): (Suspending, Verifying via revisions). Same family as `incr`. Different cycle treatment — Salsa aborts on cycle by default and offers an opt-in recovery pattern; `incr` returns `Result[T, ReadError]` from the default read.
- **Shake** (Haskell build tool): (Suspending, Verifying via content hashes). Same scheduler shape as `incr`. Different rebuilder — hashes enable cross-process caching but require explicit hash computation per task; revisions don't.
- **alien-signals / Vue 3.6 reactivity**: (Suspending, Verifying) but with a push-pull-hybrid bolt-on — the push phase pre-marks subtrees as `Pending` before any read. See [comparison-with-alien-signals.md](./comparison-with-alien-signals.md) for the full bilateral comparison.

### Operational Vocabulary for Current `incr`

Use these names consistently in design notes, issue triage, and tests. They describe the current engine; they are **not** pluggable extension points.

| Name | In `incr` | Responsibility |
|---|---|---|
| **Task** | A `Derived` compute closure | Produces one value and discovers dependencies by reading other cells. |
| **Scheduler** | The `pull_verify` traversal | Decides which stale dependency to verify next, using suspension/recursion rather than a precomputed topological order. |
| **Rebuilder** | Revision-based verification around a derived cell | Decides whether the task must run or whether the cached value is still valid. |
| **Trace** | Last successful dependency list plus `verified_at` / `changed_at` | Records the dynamic dependencies that justify future skip/recompute decisions. |
| **Green path** | Dependency verification finds no changed dependency | Marks the cell verified without running the compute closure. |
| **Red path** | A dependency changed or the cell has no valid value | Runs the compute closure, captures a new trace, and commits the result. |
| **Early cutoff** | Backdating | Stops downstream recomputation when the red path produces an equal value. |

### Current-Model Invariants

These invariants are the hardening checklist for future refactors. A change should name which invariant it preserves or intentionally changes.

1. **Scheduler and rebuilder stay separate.** Traversal order belongs to the scheduler (`pull_verify`). The decision to reuse, recompute, or backdate belongs to the rebuilder logic around a derived cell's stored trace. Performance work should say which side it changes.
2. **The trace is the last successful dynamic read set.** Dependencies are not a static over-approximation. A conditional derived cell records the branch it actually read on the last successful recompute, and a later successful recompute replaces that trace.
3. **Failed computations do not create valid traces.** Cycle errors, raised failures, and aborting reads must not install a new dependency list or cache entry. Cleanup may restore flags, but the previous successful trace remains the last authority.
4. **A stale derived cell may skip recomputation only by proof.** The proof is either the current-revision fast path, a durability shortcut, or a dependency walk showing no dependency has `changed_at` after the cell's previous verification point. A push dirty bit alone is not enough for pull-mode correctness.
5. **Backdating is the early-cutoff boundary.** If recomputation returns an equal value, `verified_at` advances but `changed_at` is preserved. Dependents compare dependency `changed_at` values against their own verification point, so preserving `changed_at` is what prevents downstream work.
6. **Dependency replacement must update both directions.** When a successful recompute discovers a different dependency set, the forward dependency list and reverse subscriber links must be diffed together. Otherwise GC, push reachability, and later verification disagree about graph shape.
7. **Constructive caching is opt-in research.** The default trace stores revisions, not content hashes or serialized values. Cross-session or content-addressed reuse requires a separate cacheable-query contract; it should not leak into ordinary `Derived` reads.

Useful regression-test names follow the same vocabulary: "dynamic dependency replacement", "green path skips recompute", "backdating early cutoff", "failed read does not record dependency", and "cycle cleanup preserves previous trace".

## Core Concepts

### Inputs and Deriveds

The library's core pull-mode building blocks are two cell types:

- **`Input[T]`** — an input cell. Its value is set externally by the user via `set()`. Inputs are the leaves of the dependency graph.
- **`Derived[T]`** — a derived cell. Its value is computed by a user-provided function that may read other inputs and derived cells. Derived cells are the interior nodes of the dependency graph.

This two-tier model keeps the API surface small while supporting arbitrarily complex computation graphs.

### The Dependency Graph

The dependency graph is **implicit** and **dynamically discovered**. There is no upfront declaration of which derived cells depend on which inputs. Instead, when a derived cell's compute function runs, every `Input::get()` or `Derived::get()` call it makes is recorded as a dependency. This means:

- Dependencies can change between recomputations (a derived cell might conditionally read different inputs).
- The graph is rebuilt each time a derived cell recomputes, always reflecting the current computation structure.

### Revisions as a Global Clock

A **Revision** is a monotonically increasing integer that serves as the system's logical clock. Each time an input's value changes, the global revision is bumped. Every cell records two timestamps:

- **`changed_at`** — the revision at which this cell's value last actually changed.
- **`verified_at`** — the revision at which this cell was last confirmed to be up-to-date.

These two timestamps are the foundation of the verification algorithm. A cell is stale if `verified_at < current_revision`. A cell has changed (relative to some observer) if `changed_at > observer.verified_at`.
`Revision` derives ordering, so the implementation uses direct comparison operators (`<`, `<=`, `>`, `>=`) for these checks.

## Automatic Dependency Tracking

### The Tracking Stack

The `Runtime` maintains a `tracking_stack`: an array of `ActiveQuery` frames. Each frame collects the `CellId`s of every cell read during a single derived-cell computation.

The mechanism works as follows:

1. When a derived cell needs to recompute, it pushes a new `ActiveQuery` frame onto the stack (`Runtime::push_tracking`).
2. The compute function runs. Every `Input::get()` or `Derived::get()` call invokes dependency recording, which appends the read cell's ID to the top frame.
3. When the compute function returns, the frame is popped (`Runtime::pop_tracking`) and the collected dependency list is stored on the cell's `MemoData`.

### Deduplication

If a compute function reads the same cell multiple times, `ActiveQuery::record` deduplicates using a `HashSet[CellId]`. This gives O(1) cost per recorded dependency while keeping the dependency list minimal and order-preserving.

### Transparency

From the user's perspective, dependency tracking is invisible. Users write ordinary functions that call `get()` on inputs and derived cells. The framework handles everything behind the scenes — no manual dependency declarations, no subscription management.

## The Verification Algorithm (`pull_verify`)

The core of the framework is the `pull_verify` function in `cells/internal/kernel/verify.mbt` (with a thin `Runtime::pull_verify` delegator in `cells/verify.mbt`). Given a cell ID, it verifies whether the cell is up-to-date at the current revision, recomputing if necessary.

### For Input Cells

Trivial: inputs are always fresh — their `changed_at` is updated atomically on every `set()`. `pull_verify` dispatches via `cell_index` and returns immediately.

### For Derived Cells

The algorithm for derived cells has several fast paths before falling back to a full dependency walk:

**1. Already verified (fast path)**

```
if cell.verified_at >= current_revision:
    return Ok(())
```

If the cell was already verified during this revision, return immediately.

**2. Root durability shortcut**

```
if durability_last_changed[cell.durability] <= cell.verified_at:
    cell.verified_at = current_revision
    return Ok(())
```

If no input of this cell's durability level (or lower) has changed since the cell was last verified, the cell cannot have changed. This skips the entire dependency walk.

**3. Cycle detection**

```
if cell.in_progress:
    report cycle
```

If we encounter a derived cell that is already being verified, we have a cycle.

**4. Dependency walk**

```
for each dependency:
    if dep is Input:
        if input.changed_at > cell.verified_at: changed = true; break
    if dep is Derived:
        push PullVerifyFrame and recurse iteratively
```

Iteratively check each dependency using an explicit stack of `PullVerifyFrame`s. Input dependencies are checked inline via direct SoA array access; derived dependencies push a new frame onto the explicit stack. This prevents stack overflow on deep dependency graphs — tested with chains of 250+ levels. When `changed = true`, `dep_cursor` is set to the end of the dependency list to short-circuit remaining checks.

Per-dep durability shortcuts also apply: before pushing a frame for an intermediate stale dep, check its durability against `verified_at`. If that durability level hasn't changed, the dep can be skipped.

**5a. If a dependency changed — recompute**

Run the type-erased compute closure, which calls the typed recompute path (`Runtime::memo_force_recompute` in `cells/derived_impl.mbt`). This is where backdating happens: the `backdate_eq` closure captured at construction compares old and new values, and if it returns `true`, `changed_at` is not updated.

**5b. If no dependency changed — green path**

Mark `verified_at = current_revision`. The cell is confirmed unchanged without recomputation.

## Backdating — The Key Insight

Backdating is the most important optimization in the framework. It prevents unnecessary recomputation from propagating through the graph.

### What Backdating Means

When a derived cell recomputes and produces the **same value** as before, its `changed_at` revision is **not updated**. It keeps its old `changed_at` timestamp, which tells downstream cells "nothing changed here."

### Concrete Example

Consider this graph:

```
input(4) → is_even(true) → label("even")
```

1. Initial state: `input = 4`, `is_even = true`, `label = "even"`. All cells have `changed_at = R1`.
2. User sets `input = 6`. Global revision bumps to `R2`. `input.changed_at = R2`.
3. `label.get()` is called. `label` is stale (`verified_at < R2`).
4. Verification walks to `is_even`, which walks to `input`. `input.changed_at = R2 > is_even.verified_at`, so `is_even` must recompute.
5. `is_even` recomputes: `6 % 2 == 0` → `true`. This is the **same value** as before.
6. **Backdating**: `is_even.changed_at` stays at `R1` (not updated to `R2`). `is_even.verified_at = R2`.
7. Back in `label`'s verification: `is_even.changed_at = R1`, which is not after `label.verified_at = R1`. No dependency changed.
8. **Green path**: `label` is confirmed unchanged. Its compute function never runs.

Without backdating, step 6 would set `is_even.changed_at = R2`, and `label` would needlessly recompute `"even"` again. In deep or wide graphs, this cascading recomputation can be very expensive. Backdating cuts it off at the earliest point where a value stabilizes.

### Backdating Strategies

The backdate decision is captured at construction as a `(T, T) -> Bool` closure. Three constructors provide different strategies:

- **`Derived::Derived` (i.e. `Derived(rt, fn)`), requires `T : Eq`** — uses `a == b` (structural equality). The standard choice when `T` implements `Eq` cheaply.
- **`Derived::with_backdate`, requires `T : BackdateEq`** — uses `a.backdate_equal(b)`. The default `BackdateEq` implementation compares `changed_at` revisions (O(1)), which is useful when `T` embeds a revision stamp and structural equality would be O(n). The default can be overridden for custom logic.
- **`Derived::derived_no_backdate`, no constraint on `T`** — always returns `false`; `changed_at` always advances on recomputation. Use this when downstream consumers always need to rerun, or when `T` has no suitable equality.

All three constructors share the same read methods (`get`, `read`, `get_or_abort`, `read_or_abort`), which carry no equality constraint — the equality decision was baked into the closure at construction time. `Scope::derived` / `Scope::derived_no_backdate` and the `Input::derived` / `Derived::map` families apply the same strategies with scope ownership or single-upstream sugar.

## ReachableDerived — Pull Recomputation, Push Reachability

`ReachableDerived` exists to solve a *GC reachability* problem, not an invalidation problem.

Pure pull verification (`Derived`) has excellent worst-case avoidance: cells never recompute unless read. But when downstream push-reactive nodes (`EagerDerived`, `Effect`) subscribe through derived values, push propagation bridges through those derived cells transparently — and a `gc()` sweep that doesn't see the upstream chain as reachable from a live root would reclaim the intermediate cells.

`ReachableDerived` participates in `push_reachable_count`, so a live `EagerDerived`/`Effect` observer downstream keeps the cell and its upstream alive across `Runtime::gc()`. Recomputation is unchanged: staleness is detected on read by the standard `verified_at < current_revision` check, through the same `pull_verify` path as `Derived`. There is no separate dirty flag.

`ReachableDerived` and `Derived` share a single SoA array (`MemoData` entries), distinguished by a flag and by `CellRef` variant, so the verification engine handles both through the same code path. See [`cells/internal/pull/memo_data.mbt`](../../incr/cells/internal/pull/memo_data.mbt).

### Push vs Pull Propagation

Push propagation BFS-walks downstream from changed sources in topological order, passing through pull derived cells as transparent bridges to reach push-reactive and push-effect nodes. An inner pruning gate (`push_reachable_count`) skips branches with no downstream push cells. Only `EagerDerived` and `Effect` contribute to the push node count — `ReachableDerived` relies on revision-based staleness detection instead. See [`cells/push_propagate.mbt`](../../incr/cells/push_propagate.mbt) and [`cells/internal/kernel/push_propagate.mbt`](../../incr/cells/internal/kernel/push_propagate.mbt).

## Durability Tiers

Three durability levels (Low, Medium, High) classify how often an input changes. The runtime tracks per-durability revision timestamps. When an input changes, all levels up to its durability are stamped. During verification, a single comparison against this array lets entire stable subtrees skip dep-walking — if no input at the cell's durability level changed, verification is a no-op. Derived cells inherit the minimum durability of their dependencies.

## Type Erasure via Per-Engine SoA

The runtime stores cells in per-engine Structure-of-Arrays (SoA) grouped by propagation mode: pull-mode inputs and deriveds, push-mode reactives and effects, and datalog relations/rules. Typed values stay in user-facing handles (`Input[T]`, `Derived[T]`); the runtime sees only type-erased closures and metadata. Dispatch tables provide uniform behavioral access via trait objects indexed by `CellId`. See [`cells/internal/kernel/state.mbt`](../../incr/cells/internal/kernel/state.mbt) for the SoA layout and [`cells/internal/shared/cell_ops.mbt`](../../incr/cells/internal/shared/cell_ops.mbt) for the trait interfaces.

This design means the verification algorithm operates entirely on `PullInputData`/`MemoData` without knowing any value types, and the batch commit logic can commit pending input values without knowing their types.

### Reference Semantics Invariant

The entire framework relies on MoonBit's reference semantics for mutable structs. Because `MemoData` and `PullInputData` have `mut` fields, they are heap-allocated — every variable, function parameter, or array slot holding one is a reference to the same object, not a copy. This means:

- Indexed SoA access (`pull.memos[idx]`, `pull.inputs[idx]`) returns a reference to the canonical entry, not a detached copy.
- The `PullVerifyFrame` stack in `cells/internal/kernel/verify.mbt` stores `memo_idx : Int` rather than a direct reference. The loop accesses `pull.memos[frame.memo_idx]` (the kernel takes the pull state as an explicit parameter) to perform mutations. Mutations to `in_progress`, `verified_at`, or `changed_at` affect the runtime's canonical `MemoData`.
- Forced recomputation (`Runtime::memo_force_recompute`) mutates the canonical `MemoData` fields directly via the same indexed-array access.

If `MemoData` or `PullInputData` were ever changed to value types, this invariant would break — mutations would apply to copies, not originals, and the framework would silently produce incorrect results (e.g., `in_progress` flags stuck `true`, causing false cycle detection).

**Important**: `PullVerifyFrame` is a simple struct with primitive fields (`memo_idx`, `dep_cursor`, `changed`, `cell_id`). To avoid potential copy semantics issues, the iterative verification loop accesses stack frames via `stack[top].field` directly rather than `let frame = stack[top]`. This ensures mutations to `dep_cursor` and `changed` persist correctly regardless of MoonBit's struct assignment semantics.

## Cycle Detection

### The Approach

Each `MemoData` has an `in_progress : Bool` flag. It is set to `true` when a derived cell enters verification or recomputation, and cleared when the operation completes. (Inputs cannot participate in cycles since they have no compute function.)

### Where Detection Fires

Cycle detection triggers in two places:

1. **During verification**: if `pull_verify` encounters a `MemoData` with `in_progress == true`, it means we iteratively reached a cell that is currently being verified — a cycle. The path is built from the local `PullVerifyFrame` stack (traversal order).
2. **During initial computation**: if forced recomputation encounters a cell with `in_progress == true`, it means the compute function (directly or indirectly) tried to read its own value — also a cycle.

### Error Handling

Cycle detection produces a `CycleError`, surfaced to readers wrapped in `ReadError`:

```moonbit
pub suberror CycleError {
  CycleDetected(CellId, Array[CellId], Array[String?])
  //            ^culprit ^cycle_path    ^labels (snapshot, capped)
}

pub enum ReadError {
  Cycle(CycleError)
  Disposed(CellId)
}
```

**Two read families:**
- `Derived::get()` (in-graph) and `Derived::read()` (outside the graph) — return `Result[T, ReadError]` for graceful handling.
- `Derived::get_or_abort()` / `Derived::read_or_abort()` — abort on error; use only where a cycle or disposed read is a programming defect.

### Dependency Recording on Failure

A critical invariant: **failed reads do not record dependencies**. This prevents spurious cyclic edges in the dependency graph.

Without this invariant, a self-referential derived cell that handles its cycle error would have itself as a dependency. On subsequent revision bumps, verification would see the self-edge and falsely detect a cycle instead of recomputing with the handled fallback value.

The fix: `get()` only records a dependency after confirming the read succeeded. Error paths return without recording.

### Stack Cleanup

When an error occurs during the iterative verification walk, the cleanup path clears `in_progress` flags on all `MemoData` entries in the verification stack. This restores consistent state so subsequent operations work correctly.

## Batch Updates

### The Problem

Without batching, each `Input::set()` call bumps the global revision independently. If a user needs to update multiple inputs atomically (e.g., setting both `x` and `y` coordinates), intermediate states are visible to reads, and each set triggers a separate verification pass.

### Two-Phase Batch Commit

`Runtime::batch(fn)` groups multiple input updates into a single revision:

1. **Write phase**: inside the batch closure, `Input::set()` stores new values as `pending_value` on the input rather than committing immediately. The actual `value` field is unchanged, so any `get()` calls during the batch see the pre-batch values (transactional semantics — reads don't see uncommitted writes). Each input registers a type-erased `commit_pending` closure on its `PullInputData`.

2. **Commit phase**: when the outermost batch ends, the runtime iterates over the pending `&Committable` entries and calls each entry's `do_commit()` via the `Committable` trait object. Each `do_commit()` invokes the input's `commit_pending` closure, which compares the pending value against the current value using `Eq`. Only inputs whose values actually changed are marked with the new revision. The pending list is then cleared.

### Raised Error Rollback

If the batch closure raises, the runtime rolls back pending writes:

- Only writes made in the failing batch frame are rolled back
- `pending_value` and registration state are restored to the pre-frame snapshot
- Inputs first registered by the failing frame are removed from the pending list
- `batch_max_durability` is recomputed from the remaining pending writes
- `batch_depth` is restored before re-raising

This keeps runtime state consistent after recoverable (raised) failures, including nested failures caught by outer batches.

### Abort Limitation

MoonBit `abort()` is not catchable. If user code aborts inside a batch closure, rollback hooks cannot run.

### Revert Detection

The two-phase design enables revert detection: if an input is set to a new value and then set back to its original value within the same batch, the commit phase sees no net change. No revision bump occurs, and downstream derived cells skip verification entirely.

### Nested Batches

Batches can be nested. A `batch_depth` counter tracks nesting, and each `Runtime::batch` call pushes a rollback frame.

- On successful inner batch completion, its rollback entries are merged into the parent frame.
- On inner failure, only that frame is rolled back before re-raising.
- Only the outermost successful batch triggers the commit phase.

## Commit-Path Extension Point (`MemoCommitPhase`)

Cross-cutting concerns that must observe every pull-mode recompute register a `MemoCommitPhase` implementor on the `Runtime` instead of editing the recompute path. Implementors receive `before_recompute` / `after_success` / `after_abort` around each recompute. Hooks fire in registration order; `before_recompute` precedes the tracking-stack push, `after_abort` fires in the catch arm before the frame is popped, and `after_success` fires *after* the cell-level epilogue (post-`changed_at`, post-`verified_at`) so backdating is observable to the hook.

Current implementors: the accumulator commit hook (`cells/accumulator_commit_hook.mbt`) and the event broadcast hook (`cells/event_broadcast_hook.mbt`). See the [T1b ADR](../decisions/2026-05-17-t1b-memo-commit-phase.md) for the trait's contract and placement rationale, and the [Derived Event Observation ADR](../decisions/2026-05-17-memo-event-observation.md) for the event tap built on it.

## Comparison with alien-signals

[alien-signals](https://github.com/nicepkg/alien-signals) is a high-performance reactive framework that uses different design trade-offs. Several ideas from alien-signals have influenced `incr`:

### Ideas adopted

- **SoA array storage**: like alien-signals' flat arrays for dependency/subscriber links, `incr` uses per-engine SoA arrays with O(1) dispatch via `CellRef` instead of a HashMap. This gives O(1) cell lookup with better cache locality than a single heterogeneous array.
- **HashSet deduplication**: efficient O(1) dependency deduplication during tracking, similar to alien-signals' link-based dedup.
- **Batch updates with two-phase values**: alien-signals buffers writes during batches. `incr` adopted this pattern with `pending_value` and commit closures on `PullInputData`, enabling revert detection.
- **Iterative graph walking**: alien-signals uses iterative propagation. `incr` uses an iterative `pull_verify` with an explicit `PullVerifyFrame` stack to prevent stack overflow on deep graphs.
- **Subscriber (reverse) links**: `incr` maintains bidirectional edges — each cell knows both its dependencies (forward) and its subscribers (reverse). Subscriber links enable push-reachability tracking and are the foundation of `ReachableDerived` and push-reactive cells.
- **Push-pull hybrid**: `ReachableDerived` cells stay reachable while a downstream `EagerDerived`/`Effect` observer is attached (push-reachability), but recomputation is the standard lazy revision check (pull). See the [ReachableDerived section](#reachablederived--pull-recomputation-push-reachability) above.

### Ideas deferred

- **Effect system**: alien-signals has first-class effect nodes integrated with its graph. `incr` has push-based `EagerDerived` and `Effect`, but no higher-level effect abstraction integrated with the pull graph.
- **Link-list storage for subscriber edges**: measured at 1.2–1.5× realistic speedup for `incr`'s already-SoA layout; deprioritized. See [docs/performance/](../performance/) for the measurement snapshots.

## Package Map

Detailed algorithms above name their home files inline. For the full,
current package layout, [docs/architecture.md](../architecture.md) is the
canonical map and the per-package `pkg.generated.mbti` files are the canonical
API surface — this section only orients you. Paths are relative to the `incr/`
library module.

| Package | Owns |
|---|---|
| root (`incr.mbt`, `traits.mbt`) | `pub using` re-exports of all public types; `RuntimeContext`/`Database`/`Readable` traits and `create_*` / `batch` helper functions |
| `types/` | Pure value types: `Revision`, `Durability`, `CellId`, `CycleError`, `ReadError`, id types, `InternTable` |
| `cells/` | Typed handles (`Input`, `Derived`, `ReachableDerived`, `DerivedMap`, `InputField`, `EagerDerived`, `Effect`, `AcceptedDerived`, `Accumulator`, datalog handles), `Runtime` coordinator, `Scope`/`Watch`/`Observer` lifecycle, batch frontend, introspection. Facade constructors live in `cells/target_facade.mbt`; recompute bodies in `cells/derived_impl.mbt` |
| `cells/internal/shared/` | Cross-engine leaf abstractions: `CellOps`, `Committable`, `CellMeta`, `CellRef`, `SlotSnapshot` |
| `cells/internal/pull/` | Pull-engine SoA entries: `PullInputData`, `MemoData` |
| `cells/internal/push/` | Push-engine SoA entries: `PushReactiveData`, `PushEffectData` |
| `cells/internal/datalog/` | Datalog SoA entries: `RelationData`, `FunctionalRelationData`, `RuleData` |
| `cells/internal/kernel/` | Graph mechanics and coordinator primitives: runtime state structs and phase machine (`state.mbt`), `pull_verify` (`verify.mbt`), push propagation, fixpoint, batch commit, tracking stack, subscriber diff, dispose/gc, cycle construction, evaluation events |

Tests: unit tests (`*_test.mbt`) and whitebox tests (`*_wbtest.mbt`) live
next to the code in `incr/cells/`; integration tests exercising the full
public API live in `incr/tests/`. Test file names follow the feature they
cover — start from the feature's source file name.

Engine-isolation invariants (no cross-engine imports, `shared` is the leaf,
kernel is one-way) are enforced by `scripts/check-engine-isolation.sh`; see
[CLAUDE.md](../../CLAUDE.md) for the current invariant list.

## Architecture Analysis (2026-04-16)

> **Status: HISTORICAL — the migration described below is complete.** This section is preserved as the design rationale that drove R1 (the kernel split, completed 2026-04-25). For the current architecture, see the package map above and the [Engine isolation](#engine-isolation-2026-04-18) paragraph. Line counts and type names below describe the pre-split codebase. See [`docs/decisions/2026-04-26-r2-runtime-decomposition-deferred.md`](../decisions/2026-04-26-r2-runtime-decomposition-deferred.md) for why no further structural decomposition is planned.

### Change Pressures

1. **Runtime is a gravity well** — at the time, `runtime.mbt` owned state for four independent propagation modes (pull, push, hybrid, datalog), plus batch management, GC, tracking, revision management, subscriber maintenance, and introspection. Every new feature touched this file.
2. **Cross-engine guards are ad-hoc** — `in_fixpoint`, `in_push_propagation`, `batch_depth > 0`, `tracking_stack.is_empty()` — four boolean/int guards scattered across `gc()`, `fixpoint()`, `push_propagate_from()`, `pull_verify()`, and input/dispose paths. Each new engine interaction required auditing all guard sites.
3. **Subscriber diff duplication** — the recompute path and the tracking epilogue both diffed old/new deps and updated subscriber links with slightly different optimizations.
4. **Future features will intensify these pressures** — accumulators need a second dependency graph. Persistent caching needs serialization hooks. Parallel computation needs thread-safety. All blocked by the monolithic structure.

### Current State (at the time)

Runtime mixed three layers: **policy** (revision management, durability shortcuts), **orchestration** (batch commit sequencing, push-then-callback ordering), and **infrastructure** (SoA allocation, free-list management, dispatch table bookkeeping). The system had distinct phases (idle → batch → commit → push-propagate → idle; idle → fixpoint-loop → publish → idle) encoded as boolean flags rather than a typed state machine.

### Target: Coordinator + Engines

```text
Runtime (coordinator + phase machine)
├── RevisionState    — revision counter, durability tracking
├── TrackingState    — tracking stack, dependency recording
├── BatchState       — pending writes, commit, rollback
├── PullState        — input/derived SoA, pull_verify
├── PushState        — reactive/effect SoA, push_propagate
├── DatalogState     — relation/rule SoA, fixpoint
├── LifecycleState   — GC root counts, scope management
└── DispatchTable    — cell_index, cell_ops, cell_lifecycle
```

### Boundary Rules

1. **Engines must not import other engines.** Cross-engine communication goes through the coordinator's `publish_cell_changes` protocol.
2. **Engines must not read RuntimePhase.** Only the coordinator checks and transitions phases.
3. **DispatchTable is read-only from engines.** Only the coordinator and allocation paths write to `cell_index`/`cell_ops`/`cell_lifecycle`.
4. **Use MoonBit `internal` packages for engine isolation.** `cells/internal/pull/`, `cells/internal/push/`, `cells/internal/datalog/` — visible to `cells/` and children, invisible to external consumers. Engine types use default (abstract) visibility; coordinator stays in `cells/`; whitebox tests stay in `cells/`.

### Migration Stages

| Stage | Description | Risk | Dependencies |
|-------|-------------|------|--------------|
| 1 | **Phase Machine** — Replace boolean guards with `RuntimePhase` enum | Low | None |
| 2 | **Extract RevisionState + TrackingState** — Group fields within RuntimeCore | Low | None |
| 3 | **Extract BatchState** — Separate batch management | Medium | Stage 2 |
| 4 | **Unify Subscriber Diff** — Single `diff_and_update_subscribers` function | Low | None |
| 5 | **Internal package split** — Move engine types to `cells/internal/` | Medium | Stages 1-3 |
| 6 | **Further engine extraction** — Deferred until accumulators create need | — | Stage 5 |

All stages preserved the public API with zero breaking changes.

### Engine isolation (2026-04-18)

Engine SoA storage is partitioned into internal sub-packages under `cells/internal/` using MoonBit's `internal` package visibility. Engines cannot import each other, and no engine package imports back into `cells/` — invariants enforced by `scripts/check-engine-isolation.sh`. All pull-, push-, and datalog-engine SoA types live in their respective `cells/internal/` sub-packages; `cells/` retains typed handles, algorithms, and cross-cutting coordinator services. Lifecycle trait impls (e.g. `pull_memo_lifecycle.mbt`) stay in `cells/` because they compose coordinator-owned capabilities — this is dispatch wiring, not SoA storage. The [Stage 5 design spec](specs/2026-04-18-incr-stage5-internal-split-design.md) carries the concrete type names and file map as of that stage.

As of R1 Stage 4 (merged 2026-04-24), `cells/internal/kernel/` owns the runtime state sub-structs, phase machine, graph-mechanics algorithms, AND coordinator primitives — see the package map above for the current file-level breakdown. A `SlotSnapshot` trait in `cells/internal/shared/` lets kernel-side verify query accumulator slot state without depending on the (coordinator-owned) `SlotMeta` struct; `Runtime` threads an `Array[&SlotSnapshot]` to `pull_verify` as an explicit parameter. `cell_lifecycle` is intentionally kept on `Runtime` (not `RuntimeCore`) because `CellLifecycle::dispose_cell` references `Runtime` directly; kernel `gc`/`gc_sweep` take a `dispose_fn : (CellId) -> Unit` callback to keep per-kind dispatch reachable without retyping the trait. The R1 plan ([archive/completed-phases/2026-04-21-r1-engine-package-split.md](../archive/completed-phases/2026-04-21-r1-engine-package-split.md)) has the full migration schedule. As of R1 Stage 5 (merged 2026-04-25), `scripts/check-engine-isolation.sh` enforces four invariants: (1) no cross-engine sibling imports among `pull`/`push`/`datalog`; (2) `internal/shared` imports no other internal packages; (3) no back-edges from any internal package (engines, shared, kernel) to `cells/` top-level; (4) kernel is one-way — engines and shared must not import kernel, only `cells/*.mbt` may. Together these guarantee kernel can import engines + shared without forming a cycle.
