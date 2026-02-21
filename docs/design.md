# Design — How incr Works Under the Hood

> **Note for users**: If you're new to `incr`, start with the [Getting Started](getting-started.md) guide and [Core Concepts](concepts.md). This document is for contributors or users who want to understand the implementation deeply.

> **Note:** The introspection API (Phase 2A) is now available. See the [Phase 1 Introspection Design](plans/2026-02-16-introspection-api-phase1-design.md) for details on the accessor methods and `CellInfo` structure.

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

`incr` uses a pure pull-based strategy: `Signal::set()` only bumps a revision counter and records the change. All verification and recomputation happens lazily when `Memo::get()` is called.

## Core Concepts

### Signals and Memos

The library has two cell types:

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
3. When the compute function returns, the frame is popped (`Runtime::pop_tracking`) and the collected dependency list is stored on the Memo's `CellMeta`.

### Deduplication

If a compute function reads the same cell multiple times, `ActiveQuery::record` deduplicates using a `HashSet[CellId]`. This gives O(1) cost per recorded dependency while keeping the dependency list minimal and order-preserving.

### Transparency

From the user's perspective, dependency tracking is invisible. Users write ordinary functions that call `get()` on Signals and Memos. The framework handles everything behind the scenes — no manual dependency declarations, no subscription management.

## The Verification Algorithm (`maybe_changed_after`)

The core of the framework is the `maybe_changed_after` function in `verify.mbt`. Given a cell and a revision, it answers: "has this cell's value changed after the given revision?"

### For Input Cells

Trivial: compare `changed_at > after_revision`.

### For Derived Cells

The algorithm for derived cells has several fast paths before falling back to a full dependency walk:

**1. Already verified (fast path)**

```
if cell.verified_at == current_revision:
    return cell.changed_at > after_revision
```

If the cell was already verified during this revision, return immediately.

**2. Durability shortcut**

```
if durability_last_changed[cell.durability] <= after_revision:
    mark verified, return false
```

If no input of this cell's durability level (or lower) has changed since `after_revision`, the cell cannot have changed. This skips the entire dependency walk.

**3. Cycle detection**

```
if cell.in_progress:
    abort("Cycle detected")
```

If we encounter a cell that is already being verified, we have a cycle.

**4. Dependency walk**

```
for each dependency:
    if maybe_changed_after(dependency, cell.verified_at):
        any_dep_changed = true; break
```

Iteratively check each dependency using an explicit stack of `VerifyFrame`s (replacing the original recursive implementation). Input dependencies are checked inline; derived dependencies push a new frame. This prevents stack overflow on deep dependency graphs — tested with chains of 250+ levels. Stop at the first dependency that changed.

**5a. If a dependency changed — recompute**

Call `recompute_and_check()` to run the Memo's compute function. This is where backdating happens: if the new value equals the old value, `changed_at` is not updated.

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

## Durability Levels

### Three Tiers

Durability classifies how often an input is expected to change:

| Level    | Index | Typical Use |
|----------|-------|-------------|
| **Low**  | 0     | Frequently changing data (source text, user input) |
| **Medium** | 1   | Moderately stable data |
| **High** | 2     | Rarely changing data (configuration, schemas) |

### Per-Durability Revision Tracking

The `Runtime` maintains a `durability_last_changed` array (one entry per durability level). When a Signal changes, `bump_revision` updates the entry for its durability level **and all lower levels**:

```
for i = 0 to durability.index():
    durability_last_changed[i] = current_revision
```

This means a High-durability change also marks Medium and Low as changed, which is correct: a High change means everything might need checking.

### Derived Cell Durability

A derived cell's durability is the **minimum** of its dependencies' durabilities. If a Memo depends on both a Low and a High input, it inherits Low durability, because it could be affected by frequent changes.
`Durability` also derives ordering, so min/max durability checks use direct enum comparisons instead of helper functions.

### The Shortcut

During verification, before walking any dependencies, `maybe_changed_after` checks:

```
durability_last_changed[cell.durability] <= after_revision?
```

If true, no input at this durability level has changed, so the cell and its entire subtree can be marked verified immediately. This is powerful for stable subgraphs: if configuration inputs (High durability) haven't changed, all Memos that only depend on configuration skip verification entirely, regardless of how many Low-durability inputs changed elsewhere.

## Type Erasure Strategy

### The Problem

The `Runtime` needs to store metadata for all cells in a single collection. But cells have different value types (`Signal[Int]`, `Memo[String]`, etc.). MoonBit's type system doesn't allow heterogeneous collections.

### The Solution

The library splits each cell into two parts:

1. **Typed value**: lives in the `Signal[T]` or `Memo[T]` struct, which the user holds a reference to.
2. **Type-erased metadata**: lives in `CellMeta`, stored in an `Array[CellMeta?]` indexed directly by `CellId.id` for O(1) lookup. Contains revisions, dependencies, durability, and cell kind — all type-independent.

The bridge between typed and type-erased worlds uses closure-based type erasure:

- `CellMeta.recompute_and_check: (() -> Bool)?` — For derived cells, this closure captures the `Memo[T]` instance and calls its typed `recompute_inner()` method. The return value indicates whether the value changed. `None` for input cells.
- `CellMeta.commit_pending: (() -> Bool)?` — For input cells during a batch, this closure captures the `Signal[T]` instance and commits its pending value. Returns true if the committed value differs from the current value. Set dynamically during batch operations and cleared after commit.

This design means the verification algorithm in `verify.mbt` operates entirely on `CellMeta` without knowing any value types, and the batch commit logic in `runtime.mbt` can commit pending signal values without knowing their types.

### Reference Semantics Invariant

The entire framework relies on MoonBit's reference semantics for mutable structs. Because `CellMeta` has `mut` fields, it is heap-allocated — every variable, function parameter, array slot, or struct field holding a `CellMeta` is a reference to the same object, not a copy. This means:

- `Runtime::get_cell()` returns a reference to the canonical cell in `Runtime.cells`, not a detached copy.
- `VerifyFrame.cell` in the iterative verification stack (`verify.mbt`) references the same `CellMeta`. Mutations to `in_progress`, `verified_at`, or `changed_at` inside `finish_frame_changed` / `finish_frame_unchanged` affect the runtime's canonical cell.
- `Memo::force_recompute` retrieves a `CellMeta` via `get_cell` and mutates its fields directly.

If `CellMeta` were ever changed to a value type (e.g., via MoonBit's `#valtype` annotation), this invariant would break — mutations would apply to copies, not originals, and the framework would silently produce incorrect results (e.g., `in_progress` flags stuck `true`, causing false cycle detection).

**Important**: While `CellMeta` uses reference semantics, `VerifyFrame` is a simple struct with primitive fields (`dep_index`, `any_dep_changed`). To avoid potential copy semantics issues with `VerifyFrame`, the iterative verification loop accesses stack frames via `stack[top].field` directly rather than `let frame = stack[top]`. This ensures mutations to `dep_index` and `any_dep_changed` persist correctly regardless of MoonBit's struct assignment semantics.

## Cycle Detection

### The Approach

Each `CellMeta` has an `in_progress : Bool` flag. It is set to `true` when a cell enters verification or recomputation, and cleared when the operation completes.

### Where Detection Fires

Cycle detection triggers in two places:

1. **During verification** (`verify.mbt`): if `maybe_changed_after_derived` encounters a cell with `in_progress == true`, it means we recursively reached a cell that is currently being verified — a cycle.
2. **During initial computation** (`memo.mbt`): if `force_recompute` encounters a cell with `in_progress == true`, it means the Memo's compute function (directly or indirectly) tried to read its own value — also a cycle.

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

When an error occurs during the iterative verification walk, the `cleanup_stack()` helper clears `in_progress` flags on all frames in the verification stack. This restores consistent state so subsequent operations work correctly.

## Batch Updates

### The Problem

Without batching, each `Signal::set()` call bumps the global revision independently. If a user needs to update multiple signals atomically (e.g., setting both `x` and `y` coordinates), intermediate states are visible to memo reads, and each set triggers a separate verification pass.

### Two-Phase Batch Commit

`Runtime::batch(fn)` groups multiple signal updates into a single revision:

1. **Write phase**: Inside the batch closure, `Signal::set()` stores new values as `pending_value` on the Signal rather than committing immediately. The actual `value` field is unchanged, so any `get()` calls during the batch see the pre-batch values (transactional semantics — reads don't see uncommitted writes). Each signal registers a type-erased `commit_pending` closure on its `CellMeta`.

2. **Commit phase**: When the outermost batch ends, the runtime iterates over `batch_pending_signals` directly (not via an alias, to ensure the list clears correctly) and calls each signal's `commit_pending` closure. Each closure compares the pending value against the current value using `Eq`. Only signals whose values actually changed are marked with the new revision. The pending list is then cleared via `.clear()`.

### Revert Detection

The two-phase design enables revert detection: if a signal is set to a new value and then set back to its original value within the same batch, the commit phase sees no net change. No revision bump occurs, and downstream memos skip verification entirely.

### Nested Batches

Batches can be nested. A `batch_depth` counter tracks nesting. Only the outermost batch triggers the commit phase. Inner batches are transparent — their signal writes accumulate in the same pending set.

## Comparison with alien-signals

[alien-signals](https://github.com/nicepkg/alien-signals) is a high-performance reactive framework that uses different design trade-offs. Several ideas from alien-signals have influenced `incr`:

### Ideas adopted

- **Array-based storage**: Like alien-signals' flat arrays for dependency/subscriber links, `incr` now uses `Array[CellMeta?]` indexed by `CellId.id` instead of a HashMap. This gives O(1) cell lookup.
- **HashSet deduplication**: Efficient O(1) dependency deduplication during tracking, similar to alien-signals' link-based dedup.
- **Batch updates with two-phase values**: alien-signals buffers signal writes during batches. `incr` adopted this pattern with `pending_value` and commit closures, enabling revert detection.
- **Iterative graph walking**: alien-signals uses iterative propagation. `incr` converted its recursive `maybe_changed_after` to an iterative stack-based loop to prevent stack overflow on deep graphs.

### Ideas deferred

- **Subscriber (reverse) links**: alien-signals maintains bidirectional edges — each cell knows both its dependencies and its subscribers. This enables push-based dirty propagation and efficient cleanup. `incr` currently only has forward (dependency) edges; adding subscriber links would be a significant architectural change (see ROADMAP Phase 4).
- **Push-pull hybrid**: With subscriber links, alien-signals can eagerly propagate dirty flags on write and lazily verify on read. `incr` uses pure pull-based verification. Adopting hybrid invalidation requires subscriber links as a prerequisite.
- **Effect system**: alien-signals has first-class `Effect` nodes that trigger side effects when observed values change. `incr` is a pure computation framework with no built-in effect mechanism.
- **Automatic cleanup/GC**: alien-signals can garbage-collect unreachable nodes via subscriber reference counting. `incr` requires subscriber links before this is possible.

## File Map

### Source files

| File | Purpose |
|------|---------|
| `signal.mbt` | `Signal[T]` — input cells with same-value optimization and durability |
| `memo.mbt` | `Memo[T]` — derived cells with memoization, backdating, and dependency tracking |
| `runtime.mbt` | `Runtime` — central state, revision management, tracking stack, batch commit |
| `cell.mbt` | `CellId`, `CellMeta` — type-erased cell metadata |
| `tracking.mbt` | `ActiveQuery` — dependency recording frame with deduplication |
| `verify.mbt` | `maybe_changed_after` — core verification algorithm |
| `revision.mbt` | `Revision`, `Durability` — revision counter and durability enum |
| `cycle.mbt` | `CycleError` — cycle error type, path formatting, `CycleError::from_path` |
| `traits.mbt` | `IncrDb`, `Readable` — core public traits |
| `pipeline_traits.mbt` | `Sourceable`, `Parseable`, `Checkable`, `Executable` — experimental pipeline traits |

### Test files

| File | What it covers |
|------|----------------|
| `memo_test.mbt` | Memo behavior, backdating, dependency tracking |
| `backdating_test.mbt` | Backdating (value-unchanged skips downstream recomputation) |
| `fanout_test.mbt` | Wide dependency graphs (diamond, multi-level) |
| `callback_test.mbt` | `Runtime::on_change` global callback |
| `on_change_test.mbt` | `Signal::on_change` / `Memo::on_change` per-cell callbacks |
| `cycle_test.mbt` | Cycle detection via `get_result()` and `get()` panics |
| `cycle_path_test.mbt` | Cycle error path formatting and content |
| `verify_path_test.mbt` | Cycle detection during verification (reverification path) |
| `integration_test.mbt` | End-to-end multi-signal/memo scenarios |
| `custom_eq_test.mbt` | Custom `Eq` implementations and backdating interaction |
| `debug_test.mbt` | Debug output and formatting |
| `traits_test.mbt` | Pipeline trait (`CalcPipeline`) fixture tests |
| `signal_introspection_test.mbt` | `Signal::cell_info`, `Signal::id` |
| `memo_introspection_test.mbt` | `Memo::cell_info`, `Memo::id` |
| `runtime_introspection_test.mbt` | `Runtime::cell_info`, `CellInfo` struct |
| `introspection_integration_test.mbt` | Cross-type introspection scenarios |
| `batch_wbtest.mbt` | Batch internals: revision, revert detection, panic guards (whitebox) |
| `durability_wbtest.mbt` | Durability shortcut internals (whitebox) |
| `cell_wbtest.mbt` | `CellId::hash` properties (whitebox) |
| `signal_wbtest.mbt` | Signal internals (whitebox) |
| `verify_wbtest.mbt` | `finish_frame_changed` invariant violation abort (whitebox) |
