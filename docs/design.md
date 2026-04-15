# Design — How incr Works Under the Hood

> **Note for users**: If you're new to `incr`, start with the [Getting Started](getting-started.md) guide and [Core Concepts](concepts.md). This document is for contributors or users who want to understand the implementation deeply.

> **Note:** The introspection API (Phase 2A) is now available. See the [Phase 1 Introspection Design](archive/2026-02-16-introspection-api-phase1-design.md) for details on the accessor methods and `CellInfo` structure.

This document explains the theoretical foundations and implementation details of the `incr` library. For usage and API examples, see [README.md](../README.md). For contributor/AI guidance, see [CLAUDE.md](../CLAUDE.md).

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

`incr` started with a pure pull-based strategy and has since added a hybrid cell type:

- **`Signal`/`Memo`** — Pure pull. `Signal::set()` only bumps a revision counter. All verification and recomputation happens lazily when `Memo::get()` is called.
- **`HybridMemo`** — Hybrid push-pull. Receives dirty flags eagerly (push) when upstream signals change, but verifies and recomputes lazily on `get()` (pull). The dirty flag enables a fast-path skip when no relevant signal has changed, without a full dependency walk.

## Core Concepts

### Signals and Memos

The library's core pull-mode building blocks are two cell types:

- **Signal[T]** — An input cell. Its value is set externally by the user via `set()`. Signals are the leaves of the dependency graph.
- **Memo[T]** — A derived cell. Its value is computed by a user-provided function that may read other Signals and Memos. Memos are the interior nodes of the dependency graph.

This two-tier model keeps the API surface small while supporting arbitrarily complex computation graphs.

### The Dependency Graph

The dependency graph is **implicit** and **dynamically discovered**. There is no upfront declaration of which Memos depend on which Signals. Instead, when a Memo's compute function runs, every `Signal::get()` or `Memo::get()` call it makes is recorded as a dependency. This means:

- Dependencies can change between recomputations (a Memo might conditionally read different inputs).
- The graph is rebuilt each time a Memo recomputes, always reflecting the current computation structure.

### Revisions as a Global Clock

A **Revision** is a monotonically increasing integer that serves as the system's logical clock. Each time a Signal's value changes, the global revision is bumped. Every cell records two timestamps:

- **`changed_at`** — The revision at which this cell's value last actually changed.
- **`verified_at`** — The revision at which this cell was last confirmed to be up-to-date.

These two timestamps are the foundation of the verification algorithm. A cell is stale if `verified_at < current_revision`. A cell has changed (relative to some observer) if `changed_at > observer.verified_at`.
`Revision` derives ordering, so the implementation uses direct comparison operators (`<`, `<=`, `>`, `>=`) for these checks.

## Automatic Dependency Tracking

### The Tracking Stack

The `Runtime` maintains a `tracking_stack`: an array of `ActiveQuery` frames. Each frame collects the `CellId`s of every cell read during a single Memo computation.

The mechanism works as follows:

1. When a Memo needs to recompute, it pushes a new `ActiveQuery` frame onto the stack (`Runtime::push_tracking`).
2. The Memo's compute function runs. Every `Signal::get()` or `Memo::get()` call invokes `Runtime::record_dependency`, which appends the read cell's ID to the top frame.
3. When the compute function returns, the frame is popped (`Runtime::pop_tracking`) and the collected dependency list is stored on the Memo's `MemoData`.

### Deduplication

If a compute function reads the same cell multiple times, `ActiveQuery::record` deduplicates using a `HashSet[CellId]`. This gives O(1) cost per recorded dependency while keeping the dependency list minimal and order-preserving.

### Transparency

From the user's perspective, dependency tracking is invisible. Users write ordinary functions that call `get()` on Signals and Memos. The framework handles everything behind the scenes — no manual dependency declarations, no subscription management.

## The Verification Algorithm (`pull_verify`)

The core of the framework is the `pull_verify` function in `cells/verify.mbt`. Given a cell ID, it verifies whether the cell is up-to-date at the current revision, recomputing if necessary.

### For Input Cells (Signals)

Trivial: signals are always fresh — their `changed_at` is updated atomically on every `set()`. `pull_verify` dispatches via `cell_index` and returns immediately.

### For Derived Cells (Memos)

The algorithm for derived cells has several fast paths before falling back to a full dependency walk:

**1. Already verified (fast path)**

```
if memo.verified_at >= current_revision:
    return Ok(())
```

If the cell was already verified during this revision, return immediately.

**2. Root durability shortcut**

```
if durability_last_changed[memo.durability] <= memo.verified_at:
    memo.verified_at = current_revision
    return Ok(())
```

If no input of this cell's durability level (or lower) has changed since the cell was last verified, the cell cannot have changed. This skips the entire dependency walk.

**3. Cycle detection**

```
if memo.in_progress:
    abort("Cycle detected")
```

If we encounter a memo that is already being verified, we have a cycle.

**4. Dependency walk**

```
for each dependency:
    if dep is Signal:
        if signal.changed_at > memo.verified_at: changed = true; break
    if dep is Memo:
        push PullVerifyFrame and recurse iteratively
```

Iteratively check each dependency using an explicit stack of `PullVerifyFrame`s. Input (signal) dependencies are checked inline via direct SoA array access; derived (memo) dependencies push a new frame onto the explicit stack. This prevents stack overflow on deep dependency graphs — tested with chains of 250+ levels. When `changed = true`, `dep_cursor` is set to the end of the dependency list to short-circuit remaining checks.

Per-dep durability shortcuts also apply: before pushing a frame for an intermediate stale dep, check its durability against `verified_at`. If that durability level hasn't changed, the dep can be skipped.

**5a. If a dependency changed — recompute**

Call `(memo.compute)()` to run the type-erased closure, which calls the typed `Memo[T]::recompute_inner()`. This is where backdating happens: the `backdate_eq` closure captured at construction compares old and new values, and if it returns `true`, `changed_at` is not updated.

**5b. If no dependency changed — green path**

Mark `verified_at = current_revision`. The cell is confirmed unchanged without recomputation.

## Backdating — The Key Insight

Backdating is the most important optimization in the framework. It prevents unnecessary recomputation from propagating through the graph.

### What Backdating Means

When a Memo recomputes and produces the **same value** as before, its `changed_at` revision is **not updated**. It keeps its old `changed_at` timestamp, which tells downstream cells "nothing changed here."

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

### Without Backdating

Without backdating, step 6 would set `is_even.changed_at = R2`, and `label` would needlessly recompute `"even"` again. In deep or wide graphs, this cascading recomputation can be very expensive. Backdating cuts it off at the earliest point where a value stabilizes.

### Backdating Strategies

The backdate decision is captured at memo construction as a `(T, T) -> Bool` closure. Three constructors provide different strategies:

- **`Memo::new[T : Eq]`** — uses `a == b` (structural equality). The standard choice when `T` implements `Eq` cheaply.
- **`Memo::new_memo[T : BackdateEq]`** — uses `a.backdate_equal(b)`. The default `BackdateEq` implementation compares `changed_at` revisions (O(1)), which is useful when `T` embeds a revision stamp and structural equality would be O(n). The default can be overridden for custom logic.
- **`Memo::new_no_backdate[T]`** — always returns `false`; `changed_at` always advances on recomputation. Use this when downstream consumers always need to rerun, or when `T` has no suitable equality. Requires no trait constraint on `T`.

All three constructors share the same read methods (`get`, `get_result`, `get_or`, `get_or_else`), which carry no trait constraint — the equality decision was baked into the closure at construction time.

## HybridMemo — Hybrid Push-Pull Cells

### Motivation

Pure pull-based verification (`Memo`) has excellent worst-case avoidance: cells never recompute unless read. But when downstream push-reactive nodes (`Reactive`, `Effect`) subscribe to derived values, the push propagation must bridge through those derived values to notify the reactives. With pure pull cells, the bridge is transparent — push propagation does a BFS through pull cell subscriber lists — but no individual pull cell knows whether _it_ was affected by the change without walking its dep chain.

`HybridMemo` adds a single `dirty : Bool` flag. Push propagation sets it eagerly. This gives `get()` a meaningful fast path:

- **Fast path**: `not(dirty) && verified_at >= current_revision` → return cached value immediately, no dep walk.
- **Slow path**: call `pull_verify_hybrid`, which walks deps, recomputes if needed, and clears `dirty`.

### Unified Memo Handling

`HybridMemo` and `PullMemo` share a single SoA array, distinguished by a flag and by `CellRef` variant. This lets the verification engine handle both cell types through the same code path. See [`cells/pull_memo.mbt`](../cells/pull_memo.mbt) for the unified entry layout.

### Push vs Pull Propagation

Push propagation BFS-walks downstream from changed sources in topological order, passing through pull/hybrid memos as transparent bridges to reach push-reactive and push-effect nodes. An inner pruning gate (`push_reachable_count`) skips memo branches with no downstream push cells. Only `Reactive` and `Effect` contribute to the push node count — `HybridMemo` relies on revision-based staleness detection instead. See [`cells/push_propagate.mbt`](../cells/push_propagate.mbt) and [`cells/verify.mbt`](../cells/verify.mbt).

### Durability Tiers

Three durability levels (Low, Medium, High) classify how often an input changes. The runtime tracks per-durability revision timestamps. When a signal changes, all levels up to its durability are stamped. During verification, a single comparison against this array lets entire stable subtrees skip dep-walking — if no input at the cell's durability level changed, verification is a no-op. Derived cells inherit the minimum durability of their dependencies.

### Type Erasure via Per-Engine SoA

The runtime stores cells in per-engine Structure-of-Arrays (SoA) grouped by propagation mode: pull-mode signals and memos, push-mode reactives and effects, and datalog relations/rules. Typed values stay in user-facing handles (`Signal[T]`, `Memo[T]`); the runtime sees only type-erased closures and metadata. Two dispatch tables (`cell_ops`, `cell_lifecycle`) provide uniform behavioral access via trait objects indexed by `CellId`. See [`cells/runtime.mbt`](../cells/runtime.mbt) for the SoA layout and [`cells/cell_ops.mbt`](../cells/cell_ops.mbt) for the trait interfaces.

This design means the verification algorithm in `cells/verify.mbt` operates entirely on `PullSignalData`/`MemoData` without knowing any value types, and the batch commit logic can commit pending signal values without knowing their types.

### Reference Semantics Invariant

The entire framework relies on MoonBit's reference semantics for mutable structs. Because `MemoData` and `PullSignalData` have `mut` fields, they are heap-allocated — every variable, function parameter, or array slot holding one is a reference to the same object, not a copy. This means:

- `Runtime::get_pull_memo()` returns a reference to the canonical entry in `Runtime.pull_memos`, not a detached copy.
- The `PullVerifyFrame` stack in `cells/verify.mbt` stores `memo_idx : Int` rather than a direct reference. The loop accesses `rt.pull_memos[frame.memo_idx]` to perform mutations. Mutations to `in_progress`, `verified_at`, or `changed_at` affect the runtime's canonical `MemoData`.
- `Memo::force_recompute` retrieves a `MemoData` via `get_pull_memo` and mutates its fields directly.

If `MemoData` or `PullSignalData` were ever changed to value types (e.g., via MoonBit's `#valtype` annotation), this invariant would break — mutations would apply to copies, not originals, and the framework would silently produce incorrect results (e.g., `in_progress` flags stuck `true`, causing false cycle detection).

**Important**: `PullVerifyFrame` is a simple struct with primitive fields (`memo_idx`, `dep_cursor`, `changed`, `cell_id`). To avoid potential copy semantics issues, the iterative verification loop accesses stack frames via `stack[top].field` directly rather than `let frame = stack[top]`. This ensures mutations to `dep_cursor` and `changed` persist correctly regardless of MoonBit's struct assignment semantics.

## Cycle Detection

### The Approach

Each `MemoData` has an `in_progress : Bool` flag. It is set to `true` when a memo enters verification or recomputation, and cleared when the operation completes. (Signals cannot participate in cycles since they have no compute function.)

### Where Detection Fires

Cycle detection triggers in two places:

1. **During verification** (`cells/verify.mbt`): if `pull_verify` encounters a `MemoData` with `in_progress == true`, it means we iteratively reached a memo that is currently being verified — a cycle. The path is built from the local `PullVerifyFrame` stack (traversal order).
2. **During initial computation** (`cells/memo.mbt`): if `force_recompute` encounters a memo with `in_progress == true`, it means the Memo's compute function (directly or indirectly) tried to read its own value — also a cycle.

### Error Handling

Cycle detection returns a `CycleError` type that can be handled gracefully:

```moonbit
pub suberror CycleError {
  CycleDetected(CellId, Array[CellId])  // (culprit, cycle_path)
}
```

**Two APIs:**
- `Memo::get()` — Aborts on cycle (backward compatible)
- `Memo::get_result()` — Returns `Result[T, CycleError]` for graceful handling

### Dependency Recording on Failure

A critical invariant: **failed `get_result()` calls do not record dependencies**. This prevents spurious cyclic edges in the dependency graph.

Without this invariant, a self-referential memo that handles its cycle error would have itself as a dependency. On subsequent revision bumps, verification would see the self-edge and falsely detect a cycle instead of recomputing with the handled fallback value.

The fix: `Memo::get_result()` only calls `record_dependency()` after confirming the read succeeded. Error paths return without recording.

### Stack Cleanup

When an error occurs during the iterative verification walk, the `clear_verify_stack()` helper clears `in_progress` flags on all `MemoData` entries in the verification stack. This restores consistent state so subsequent operations work correctly.

## Batch Updates

### The Problem

Without batching, each `Signal::set()` call bumps the global revision independently. If a user needs to update multiple signals atomically (e.g., setting both `x` and `y` coordinates), intermediate states are visible to memo reads, and each set triggers a separate verification pass.

### Two-Phase Batch Commit

`Runtime::batch(fn)` groups multiple signal updates into a single revision:

1. **Write phase**: Inside the batch closure, `Signal::set()` stores new values as `pending_value` on the Signal rather than committing immediately. The actual `value` field is unchanged, so any `get()` calls during the batch see the pre-batch values (transactional semantics — reads don't see uncommitted writes). Each signal registers a type-erased `commit_pending` closure on its `PullSignalData`.

2. **Commit phase**: When the outermost batch ends, the runtime iterates over `batch_pending : Array[&Committable]` and calls each entry's `do_commit()` method via the `Committable` trait object. Each `do_commit()` invokes the signal's `commit_pending` closure, which compares the pending value against the current value using `Eq`. Only signals whose values actually changed are marked with the new revision. The pending list is then cleared via `.clear()`.

### Raised Error Rollback

If the batch closure raises, the runtime rolls back pending writes:

- Only writes made in the failing batch frame are rolled back
- `pending_value` and registration state are restored to the pre-frame snapshot
- Signals first registered by the failing frame are removed from `batch_pending`
- `batch_max_durability` is recomputed from the remaining pending writes
- `batch_depth` is restored before re-raising

This keeps runtime state consistent after recoverable (raised) failures, including nested failures caught by outer batches.

### Abort Limitation

MoonBit `abort()` is not catchable. If user code aborts inside a batch closure, rollback hooks cannot run.

### Revert Detection

The two-phase design enables revert detection: if a signal is set to a new value and then set back to its original value within the same batch, the commit phase sees no net change. No revision bump occurs, and downstream memos skip verification entirely.

### Nested Batches

Batches can be nested. A `batch_depth` counter tracks nesting, and each `Runtime::batch` call pushes a rollback frame.

- On successful inner batch completion, its rollback entries are merged into the parent frame.
- On inner failure, only that frame is rolled back before re-raising.
- Only the outermost successful batch triggers the commit phase.

## Comparison with alien-signals

[alien-signals](https://github.com/nicepkg/alien-signals) is a high-performance reactive framework that uses different design trade-offs. Several ideas from alien-signals have influenced `incr`:

### Ideas adopted

- **SoA array storage**: Like alien-signals' flat arrays for dependency/subscriber links, `incr` uses three parallel SoA arrays (`pull_signals`, `pull_memos`, `cell_index`) with O(1) dispatch via `CellRef` instead of a HashMap. This gives O(1) cell lookup with better cache locality than a single heterogeneous array.
- **HashSet deduplication**: Efficient O(1) dependency deduplication during tracking, similar to alien-signals' link-based dedup.
- **Batch updates with two-phase values**: alien-signals buffers signal writes during batches. `incr` adopted this pattern with `pending_value` and commit closures on `PullSignalData`, enabling revert detection.
- **Iterative graph walking**: alien-signals uses iterative propagation. `incr` uses an iterative `pull_verify` with an explicit `PullVerifyFrame` stack to prevent stack overflow on deep graphs.

### Ideas adopted (additions since initial implementation)

- **Subscriber (reverse) links**: `incr` now maintains bidirectional edges — each cell knows both its dependencies (forward) and its subscribers (reverse). Subscriber links enable push-based dirty propagation and are the foundation of `HybridMemo` and push-reactive cells.
- **Push-pull hybrid**: `HybridMemo` cells receive dirty flags via eager push propagation and verify/recompute lazily on `get()`. This is the hybrid model described above.

### Ideas deferred

- **Effect system**: alien-signals has first-class `Effect` nodes that trigger side effects when observed values change. `incr` has `Reactive` and `Effect` (push-based), but no higher-level effect abstraction integrated with the pull graph.
- **Automatic cleanup/GC**: alien-signals can garbage-collect unreachable nodes via subscriber reference counting. `incr` requires GC infrastructure (Phase 4 roadmap) before this is possible.

## File Map

### Package structure

The library is split into four MoonBit sub-packages. The root package re-exports all public types as transparent aliases so downstream users see a unified `@incr` API.

### Root package (`dowdiness/incr`)

| File | Purpose |
|------|---------|
| `incr.mbt` | `pub type` re-exports — transparent aliases for all public types |
| `traits.mbt` | `Database`, `Readable` — core public traits; `create_signal`, `create_memo`, `create_memo_map`, `batch` helpers |

### `types/` package (`dowdiness/incr/types`)

| File | Purpose |
|------|---------|
| `types/revision.mbt` | `Revision`, `Durability`, `DURABILITY_COUNT` — revision counter and durability enum |
| `types/cell_id.mbt` | `CellId` — cell identifier with `Hash` implementation |
| `types/cell_handles.mbt` | `SignalId[T]`, `MemoId[T]`, `ReactiveId[T]`, `RelationId[T]`, `RuleId` — phantom-typed handles |
| `types/intern_table.mbt` | `InternId`, `InternTable[T]` — grow-only value interning for stable identity |

### `cells/` package (`dowdiness/incr/cells`)

**Pull mode (lazy verification):**

| File | Purpose |
|------|---------|
| `cells/signal.mbt` | `Signal[T]` — input cells with same-value optimization and durability |
| `cells/pull_signal.mbt` | `PullSignalData` — SoA entry for input cells; `CellOps` + `Committable` impls |
| `cells/memo.mbt` | `Memo[T]` — derived cells with memoization, backdating, and dependency tracking |
| `cells/pull_memo.mbt` | `MemoData` — unified SoA entry for pull and hybrid derived cells |
| `cells/verify.mbt` | `pull_verify` — SoA-native iterative verification algorithm with `PullVerifyFrame` stack |

**Push mode (eager propagation):**

| File | Purpose |
|------|---------|
| `cells/push_reactive.mbt` | `Reactive[T]` — eagerly-recomputed derived cell; `PushReactiveData` SoA entry |
| `cells/push_effect.mbt` | `Effect` — terminal side-effect cell; `PushEffectData` SoA entry |
| `cells/push_propagate.mbt` | `push_propagate_from`, `propagate_level_change` — level-sorted eager push propagation |

**Hybrid mode (push staleness + pull verification):**

| File | Purpose |
|------|---------|
| `cells/hybrid_memo.mbt` | `HybridMemo[T]` — push-notified, pull-verified memo; uses unified `MemoData` |

**Datalog mode (fixpoint evaluation):**

| File | Purpose |
|------|---------|
| `cells/datalog_relation.mbt` | `Relation[T]` — set with delta tracking for semi-naive fixpoint |
| `cells/datalog_functional_relation.mbt` | `FunctionalRelation[K, V]` — typed map relation with optional merge |
| `cells/datalog_rule.mbt` | `Rule` — derives new facts from input relations |
| `cells/datalog_fixpoint.mbt` | `Runtime::fixpoint()` — semi-naive evaluation loop |

**Runtime, dispatch, and shared infrastructure:**

| File | Purpose |
|------|---------|
| `cells/runtime.mbt` | `Runtime` — coordinator: SoA arrays, revision management, tracking stack, batch commit, GC |
| `cells/cell.mbt` | `CellInfo` struct for introspection output |
| `cells/cell_ref.mbt` | `CellRef` enum — O(1) dispatch into per-engine SoA arrays |
| `cells/cell_ops.mbt` | `CellOps`, `CellLifecycle`, `Committable` traits; `CellMeta` shared metadata |
| `cells/tracking.mbt` | `ActiveQuery` — dependency recording frame with deduplication |
| `cells/batch.mbt` | `Runtime::batch` — two-phase commit with rollback and revert detection |
| `cells/cycle.mbt` | `CycleError` — cycle error type, path formatting |

**Lifecycle and memory management:**

| File | Purpose |
|------|---------|
| `cells/scope.mbt` | `Scope` — hierarchical cell ownership with bulk disposal |
| `cells/observer.mbt` | `Observer[T]` — keep-alive handle for untracked reads |
| `cells/memo_map.mbt` | `MemoMap[K, V]` — keyed memoization with `sweep()` for post-GC cleanup |
| `cells/tracked_cell.mbt` | `TrackedCell[T]` — field-level tracked struct wrapper |
| `cells/introspection.mbt` | `Runtime::cell_info`, `Runtime::dependents` — graph introspection |

### `pipeline/` package (`dowdiness/incr/pipeline`)

| File | Purpose |
|------|---------|
| `pipeline/pipeline_traits.mbt` | `Sourceable`, `Parseable`, `Checkable`, `Executable` — experimental pipeline traits |

### Test files

Unit tests (`*_test.mbt`) and whitebox tests (`*_wbtest.mbt`) live in `cells/`. Integration tests live in `tests/`.

| File | What it covers |
|------|----------------|
| `cells/memo_test.mbt` | Memo behavior, backdating, dependency tracking |
| `cells/memo_map_test.mbt` | MemoMap keyed caching and lazy per-key recomputation |
| `cells/backdating_test.mbt` | Backdating (value-unchanged skips downstream recomputation) |
| `cells/callback_test.mbt` | `Runtime::on_change` global callback |
| `cells/on_change_test.mbt` | `Signal::on_change` / `Memo::on_change` per-cell callbacks |
| `cells/cycle_test.mbt` | Cycle detection via `get_result()` and `get()` panics |
| `cells/cycle_path_test.mbt` | Cycle error path formatting and content |
| `cells/verify_path_test.mbt` | Cycle detection during verification (reverification path) |
| `cells/custom_eq_test.mbt` | Custom `Eq` implementations and backdating interaction |
| `cells/debug_test.mbt` | Debug output and formatting |
| `cells/introspection_test.mbt` | `Signal::cell_info`, `Memo::cell_info`, `Runtime::cell_info` |
| `cells/batch_wbtest.mbt` | Batch internals: revision, revert detection, panic guards (whitebox) |
| `cells/durability_wbtest.mbt` | Durability shortcut internals (whitebox) |
| `cells/cell_wbtest.mbt` | `CellId::hash` properties (whitebox) |
| `cells/cell_ref_wbtest.mbt` | `CellRef` dispatch and SoA index properties (whitebox) |
| `cells/signal_wbtest.mbt` | Signal internals (whitebox) |
| `cells/verify_wbtest.mbt` | `pull_verify` invariant violation abort (whitebox) |
| `cells/pull_verify_wbtest.mbt` | `pull_verify` SoA dispatch and short-circuit behavior (whitebox) |
| `cells/soa_wbtest.mbt` | SoA allocation and `cell_index` invariants (whitebox) |
| `cells/memo_dep_diff_wbtest.mbt` | Dependency diff optimization internals (whitebox) |
| `cells/runtime_wbtest.mbt` | Cross-runtime `get_pull_signal`/`get_pull_memo` abort (whitebox) |
| `cells/subscriber_wbtest.mbt` | Subscriber tracking internals (whitebox) |
| `cells/tracked_cell_wbtest.mbt` | `TrackedCell` field-level tracking internals (whitebox) |
| `cells/memo_map_wbtest.mbt` | MemoMap internal key→memo mapping (whitebox) |
| `cells/hybrid_wbtest.mbt` | `HybridMemo` internal dirty flag, fast path, backdating, push propagation (whitebox) |
| `tests/integration_test.mbt` | End-to-end multi-signal/memo scenarios |
| `tests/fanout_test.mbt` | Wide dependency graphs (diamond, multi-level) |
| `tests/traits_test.mbt` | Pipeline trait (`CalcPipeline`) fixture tests |
| `tests/tracked_struct_test.mbt` | `TrackedCell`, `Trackable`, and `gc_tracked` |
| `tests/hybrid_test.mbt` | `HybridMemo` public API: get, update, backdating, diamond, batch, chained, pull chain |

## Architecture Analysis (2026-04-16)

### Change Pressures

1. **Runtime is a gravity well** — `runtime.mbt` (789 lines) owns state for four independent propagation modes (pull, push, hybrid, datalog), plus batch management, GC, tracking, revision management, subscriber maintenance, and introspection. Every new feature touches this file.
2. **Cross-engine guards are ad-hoc** — `in_fixpoint`, `in_push_propagation`, `batch_depth > 0`, `tracking_stack.is_empty()` — four boolean/int guards scattered across `gc()`, `fixpoint()`, `push_propagate_from()`, `pull_verify()`, `Signal::set()`, and `dispose_cell()`. Each new engine interaction requires auditing all guard sites.
3. **Subscriber diff duplication** — `memo_force_recompute` and `finish_tracking` both diff old/new deps and update subscriber links with slightly different optimizations.
4. **Future features will intensify these pressures** — Accumulators need a second dependency graph. Persistent caching needs serialization hooks. Parallel computation needs thread-safety. All blocked by the monolithic structure.

### Current State

Runtime mixes three layers: **policy** (revision management, durability shortcuts), **orchestration** (batch commit sequencing, push-then-callback ordering), and **infrastructure** (SoA allocation, free-list management, dispatch table bookkeeping). The system has distinct phases (idle → batch → commit → push-propagate → idle; idle → fixpoint-loop → publish → idle) encoded as boolean flags rather than a typed state machine.

### Target: Coordinator + Engines

```text
Runtime (coordinator + phase machine)
├── RevisionState    — revision counter, durability tracking
├── TrackingState    — tracking stack, dependency recording
├── BatchState       — pending writes, commit, rollback
├── PullState        — signal/memo SoA, pull_verify (already exists as struct)
├── PushState        — reactive/effect SoA, push_propagate (already exists)
├── DatalogState     — relation/rule SoA, fixpoint (already exists)
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

All stages preserve the public API with zero breaking changes. Downstream consumer is loom's `ReactiveParser`.
