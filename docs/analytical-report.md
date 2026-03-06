# Analytical Report: `dowdiness/incr` — Incremental Recomputation Library

## 1. Overview

This is a Salsa-inspired incremental computation framework in MoonBit. It maintains a dependency graph of cells — input values (Signals) and derived computations (Memos) — and ensures that derived values are efficiently recomputed only when their transitive inputs actually change.

The library implements a **hybrid push-pull architecture** with seven cell kinds, a Structure-of-Arrays (SoA) storage layout, type-erased cell metadata, and three distinct evaluation strategies (lazy pull verification, eager push propagation, and semi-naive Datalog fixpoint).

**Total source**: ~2,700 lines of implementation across 16 `.mbt` files, with ~3,500 lines of tests across 39 test files.

---

## 2. Execution Flow in Order

### 2.1 Initialization

1. `Runtime::new()` allocates a globally unique `runtime_id` from the module-level counter `next_runtime_id`, initializes all SoA arrays to empty, sets `current_revision` to `Revision::initial()` (value 0), and initializes the `durability_last_changed` fixed-array with 3 entries (one per durability level) all at revision 0.

2. Cells are created via typed constructors (`Signal::new`, `Memo::new`, `HybridMemo::new`, `Reactive::new`, `Effect::new`, `Relation::new`, `Runtime::new_rule`). Each allocates a `CellId` via `Runtime::alloc_cell_id`, which appends to `cell_index` and auto-increments `next_cell_id`. The typed data goes into the appropriate SoA array, and a `&CellOps` trait reference is pushed to `cell_ops` for uniform dispatch.

### 2.2 Writing Input Values

When `Signal::set(new_value)` is called:

- **Outside batch**: If `value == new_value`, no-op (same-value optimization). Otherwise, calls `set_unconditional`: updates `self.value`, calls `bump_revision` (which calls `advance_revision`, incrementing `current_revision` and updating `durability_last_changed` entries up to the signal's durability index), marks the signal's `PullSignalData.changed_at = current_revision`, triggers `push_propagate_from` if any push nodes exist, fires per-signal and global `on_change` callbacks.

- **Inside batch** (`batch_depth > 0`): Stores the value as `pending_value`, registers a `commit_pending` closure on `PullSignalData`, pushes a `&Committable` reference to `batch_pending`, and records a rollback closure on the current `BatchFrame`. The actual revision bump is deferred.

### 2.3 Batch Commit

When the outermost `Runtime::batch()` closure returns:

1. `commit_batch()` enters a while loop over `batch_pending`.
2. **Phase 1**: Each `Committable.do_commit()` is called, which executes the signal's `commit` closure (comparing pending vs. current value). Changed signals are collected.
3. **Phase 2**: If any changed, a single `advance_revision(batch_max_durability)` occurs. Each changed signal's `changed_at` is stamped. Per-signal `on_change` callbacks are **snapshotted** before execution (to prevent mutation during iteration). Push propagation runs before callbacks. Callbacks may queue more signals (re-entrancy), which the while loop processes in subsequent waves.
4. After all waves, `fire_on_change()` runs exactly once.

### 2.4 Reading Derived Values (Pull Verification)

When `Memo::get()` is called:

1. **Cross-runtime guard**: If a memo computation on a different runtime is active, aborts.
2. **Fixpoint guard**: Aborts if called during `fixpoint()`.
3. **No cached value**: Calls `force_recompute()` — pushes a tracking frame, executes the compute closure (which calls `Signal::get()` / `Memo::get()` internally, recording dependencies via `record_dependency`), pops the frame, diffs old/new deps to update subscriber links, applies backdating, and stamps `verified_at`.
4. **Fast path**: If `verified_at == current_revision`, returns cached value immediately.
5. **Slow path**: Calls `pull_verify(cell_id)`.

### 2.5 The `pull_verify` Algorithm

This is the core verification algorithm. It operates on `PullMemo` cells using an **explicit stack** (array of `PullVerifyFrame`) instead of recursion:

1. **Root checks**: If already verified (`verified_at >= current_revision`), return. Durability shortcut: if `durability_last_changed[memo.durability.index()] <= memo.verified_at`, mark verified without walking deps. Cycle check: if `in_progress`, return error with path.

2. **Stack loop**: Push root frame. While stack is non-empty:
   - Advance `dep_cursor` through the current frame's memo's dependency list.
   - For each dependency:
     - **PullSignal**: Check `changed_at > memo.verified_at`. If changed, set `frame.changed = true` and skip remaining deps (short-circuit).
     - **PullMemo**: If unverified, apply durability shortcut or push a new frame (recursing). If already verified, check `changed_at`. Cycle detection via `in_progress` flag.
     - **HybridMemo**: Recursively call `pull_verify_hybrid`, then check `changed_at`.
     - **PushReactive/PushEffect/Relation/Rule**: Direct `changed_at` comparison (these are kept fresh by other mechanisms).
   - When all deps inspected: pop frame, clear `in_progress`. If any dep changed, call `(memo.compute)()` (the type-erased closure). If no dep changed (green path), just stamp `verified_at`. After popping, propagate the change status to the parent frame.

**Key properties**:
- Short-circuits on first changed dep (sets `dep_cursor` to end).
- Iterative, not recursive — bounded by dependency depth, not call stack.
- Backdating happens inside the compute closure (`Memo::recompute_inner` -> `force_recompute`), so the runtime only sees a bool.

### 2.6 Push Propagation

`push_propagate_from(changed_sources)` implements **level-sorted topological BFS**:

1. **Seeding**: For each changed source, BFS through its subscribers. Pull memos and hybrid memos are "bridged through" — the BFS continues through them to reach downstream push nodes. Push nodes (`PushReactive`, `PushEffect`) are marked dirty and enqueued in a max-priority queue with negated levels (simulating a min-heap).
   - `HybridMemo` nodes get their `dirty` flag set during this BFS and are recorded in `hybrid_dirty`.

2. **Processing**: Dequeue entries in level-ascending order (glitch-free):
   - **PushReactive**: Guard against stale entries (level mismatch), disposed cells, and clean cells. Clear dirty, recompute with tracked dependencies, diff subscriber links, recalculate level, propagate level changes. If value changed, enqueue its push subscribers (early cutoff on unchanged).
   - **PushEffect**: Same guards. Execute side effect, update deps and level. Effects are terminal — no downstream propagation.

3. Clear `hybrid_dirty` after propagation wave completes.

### 2.7 HybridMemo Verification

`HybridMemo::get()` has a unique two-tier fast path:

1. If `not(dirty) && verified_at >= current_revision` -> return cached immediately. This is the fastest path: no dep walk at all. The dirty flag is set by push propagation; if push propagation didn't reach this node, it's clean.
2. Otherwise, call `pull_verify_hybrid`, which walks deps like `pull_verify` but with a simpler (non-stack-based) linear loop. Then clear `dirty`.

### 2.8 Datalog Fixpoint

`Runtime::fixpoint()` implements **semi-naive evaluation**:

1. **Guards**: No re-entrant fixpoint, no fixpoint inside batch.
2. **Pre-scan**: Mark relations with non-empty deltas as changed.
3. **Loop**:
   a. **Drain**: Move each relation's `delta` into `current` (facts become visible to `contains`/`iter`).
   b. **Apply rules**: Each rule's `apply_delta` closure reads `delta_iter()` (the frontier) and `current`, inserting derived facts into `staged_delta`.
   c. **Convergence check**: If any relation has non-empty `staged_delta`, continue.
   d. **Promote**: Swap `staged_delta` <-> `delta` (the old frontier allocation is reused as the next staging buffer, then cleared). This is the "semi-naive" part — only new facts drive the next iteration.
4. **Post-fixpoint**: Advance revision, stamp `changed_at` on all changed relations, trigger push propagation and `on_change`.

**Three-set design**: `current` (materialized), `delta` (frontier for current iteration), `staged_delta` (newly derived, becomes next frontier). This avoids redundant rule application on already-known facts.

---

## 3. Core Logic by Component

### 3.1 `Revision` and `Durability`

`Revision` is a monotonic integer counter. `Durability` is a 3-level enum (`Low < Medium < High`). The runtime maintains `durability_last_changed[3]`, where index `i` records the last revision at which any input of durability `<= i` changed. When `advance_revision` is called with durability `d`, entries 0 through `d.index()` are updated to `current_revision`.

**Durability shortcut**: A memo with durability `d` can skip verification if `durability_last_changed[d.index()] <= memo.verified_at`. This means: "no input at my durability level or lower has changed since I was last verified."

A derived cell's durability = `min(dependency durabilities)`. This is conservative: a memo depending on both a Low and a High signal inherits Low.

### 3.2 `CellId` and `CellRef`

`CellId` = `(runtime_id, id)`. The `id` field is a direct index into `cell_index` and `cell_ops` arrays. `CellRef` is an enum dispatching to the correct SoA array and index: `PullSignal(Int)`, `PullMemo(Int)`, `HybridMemo(Int)`, `PushReactive(Int)`, `PushEffect(Int)`, `Relation(Int)`, `Rule(Int)`, or `Disposed`.

### 3.3 Type Erasure Pattern

MoonBit lacks trait objects with associated types. The bridge between typed cells (`Signal[T]`, `Memo[T]`) and the type-erased SoA storage uses **captured closures**:

- `Memo::new` creates a `Memo[T]` struct, then creates a closure `() -> Result[Bool, CycleError]` that captures the `Memo[T]` by reference. This closure calls `recompute_inner()`, which calls `force_recompute()`, which operates on `T` internally but returns only `Bool` (changed/unchanged). The closure is stored on `PullMemoData.compute`.
- Similarly, `Signal::set_batch` stores a `commit_pending` closure `() -> Bool` on `PullSignalData` that captures the `Signal[T]` and calls `commit()`.
- `Reactive::new` stores a `compute : () -> Bool` that captures a `Ref[T?]` for the typed value.

The runtime never handles `T` directly — all type-specific operations happen inside closures that cross the boundary with `Bool` or `Unit`.

### 3.4 Dependency Tracking

Dependencies are recorded via a stack of `ActiveQuery` frames on `Runtime.tracking_stack`:

- `push_tracking(cell_id)` pushes a frame and sets `current_computing_runtime_id` to this runtime's ID.
- Every `Signal::get()`, `Memo::get()`, or `Relation::iter()` call during computation invokes `record_dependency(cell_id)`, which adds to the top frame's dependency list (with HashSet deduplication).
- `pop_tracking()` returns the collected `(dependencies, seen_set)`.

After computation, the caller diffs old deps vs. new deps to maintain **subscriber links** (reverse edges): removed deps lose the subscriber, added deps gain it. This enables push propagation to find downstream nodes.

### 3.5 Batch System

Nested batches use a stack of `BatchFrame`s. Each frame records `BatchUndo` entries (one per first-write-per-signal). On error, `rollback_current_batch_frame` replays undo entries in reverse order. On success, child frame undo entries merge into the parent frame (so the parent can still roll back the child's changes if the parent fails).

Key subtlety at `runtime.mbt:800-808`: During `commit_batch`, callbacks are invoked with `batch_depth` temporarily incremented. This prevents callbacks from triggering immediate `set_unconditional` (which would bypass the batch mechanism). Instead, any `signal.set()` inside a callback takes the batch path, and the while loop in `commit_batch` processes additional waves.

### 3.6 Relation and Rule (Datalog Layer)

`Relation[T]` stores three typed `HashSet[T]` behind `Ref` wrappers. The `RelationData` SoA entry holds type-erased closures (`drain_delta`, `is_delta_empty`, `promote_staged_delta`, `is_staged_delta_empty`) that operate on these sets.

`insert()` routes to either `delta` (outside fixpoint) or `staged_delta` (during fixpoint), with deduplication against all three sets.

Rules are registered via `Runtime::new_rule` with an `apply_delta` closure, plus arrays of input/output relation CellIds (currently stored but not read — observable as compiler warnings). The `apply_delta` closure is expected to read input relations' deltas and insert derived facts into output relations.

---

## 4. Algorithms and Data Structures

| Component | Algorithm / Structure | Purpose |
|---|---|---|
| `pull_verify` | Explicit-stack DFS with short-circuiting | Lazy dependency verification without recursion |
| `push_propagate_from` | Level-sorted BFS via max-priority-queue with negated levels | Glitch-free topological push propagation |
| `propagate_level_change` | BFS worklist | Cascading level recalculation |
| `fixpoint` | Semi-naive evaluation (3-set delta tracking) | Datalog fixpoint computation |
| `ActiveQuery` | Array + HashSet | Order-preserving, deduplicated dependency collection |
| `BatchFrame` | Undo log with HashSet for first-write tracking | Nested batch rollback support |
| `cell_index` / `cell_ops` | Parallel arrays indexed by `CellId.id` | O(1) cell dispatch |
| SoA arrays | Typed arrays per cell kind | Cache-friendly storage, avoids tagged union overhead |
| `free_push_reactives` / `free_push_effects` | Free-list (stack) | Slot reuse for disposed push cells |
| `PushEntry` with negated level | Max-heap simulating min-heap | Level-ascending dequeue order |

---

## 5. State Changes and Data Flow

### Signal Set -> Memo Get (Pull-Only Path)

```
Signal::set(v)
  -> value = v
  -> bump_revision(durability)  -> current_revision++
  -> mark_input_changed(id)     -> sig.changed_at = current_revision
  -> push_propagate_from(...)   -> (if push_node_count > 0)
  -> fire_on_change()

Memo::get()
  -> pull_verify(cell_id)
    -> for each dep:
        if dep.changed_at > memo.verified_at -> changed = true
    -> if changed: (memo.compute)()
        -> force_recompute()
          -> push_tracking, run compute, pop_tracking
          -> diff deps, update subscribers
          -> backdate if value unchanged
          -> stamp verified_at
    -> else: stamp verified_at (green path)
  -> return self.value
```

### Signal Set -> Reactive (Push Path)

```
Signal::set(v)
  -> push_propagate_from([cell_id])
    -> BFS through subscribers
      -> mark PushReactive.dirty, enqueue at level
      -> mark HybridMemo.dirty (bridge through)
    -> dequeue min-level first:
      -> reactive.compute() -> updates value, returns changed?
      -> if changed: enqueue reactive's subscribers
      -> early cutoff: if unchanged, stop propagation
```

### Fixpoint

```
Relation::insert(fact) -> adds to delta (or staged_delta)

Runtime::fixpoint()
  -> loop:
    -> drain delta -> current
    -> apply all rules (read delta_iter, insert to staged_delta)
    -> promote staged -> delta, clear staged
    -> break if no new facts
  -> advance_revision, stamp changed_at, push_propagate_from
```

---

## 6. Error Handling and Edge Cases

### Cycle Detection

Two independent mechanisms:

1. **In `pull_verify`**: Each `PullMemoData` has an `in_progress` flag set true when pushed onto the verify stack. If a dep being verified is already `in_progress`, a `CycleError` is constructed from the verify stack's cell IDs plus the closing cell. The `clear_verify_stack` function cleans up all `in_progress` flags before returning the error.

2. **In `force_recompute`**: Before pushing a tracking frame, checks `cell.in_progress`. If true, constructs a `CycleError` from the tracking stack (not the verify stack). This catches cycles during initial computation (no cached value yet).

These two paths use different stacks to build the path (`collect_in_progress_path` for verify, `collect_tracking_path` for tracking), which is a subtlety worth noting.

### Cross-Runtime Guards

Every `get()` method checks `current_computing_runtime_id` against the cell's `runtime_id`. This prevents a memo on Runtime A from reading a signal on Runtime B, which would create an untrackable cross-runtime dependency. The guard resets the global sentinel before aborting to prevent state leaks.

### Fixpoint Guards

During `fixpoint()`, `Memo::get()` and `HybridMemo::get()` abort. `pull_verify` aborts on `Relation`/`Rule` deps when `in_fixpoint = true`. This prevents pull verification from interfering with the fixpoint's delta-tracking invariants.

### Batch Error Handling

If a batch closure raises (not aborts), `rollback_current_batch_frame` replays undo entries in reverse, restoring `pending_value` and removing the signal from `batch_pending`. The error is then re-raised. Nested batch success merges child undo entries into the parent, but only for signals not already tracked by the parent (preventing double-undo).

### Disposal

`dispose_reactive` and `dispose_effect` remove subscriber links, mark `cell_index[id]` as `Disposed`, clear the SoA slot's closures and sources (releasing captured references), push the index to the free list, and decrement `push_node_count`. Subsequent `push_propagate_from` checks for disposal via `cell_index` match before processing.

---

## 7. Assumptions and Uncertainties

### Confirmed from code:

- **Single-threaded**: The global `current_computing_runtime_id : Ref[Int]` sentinel and the absence of any synchronization primitives confirm single-threaded design. The code comments acknowledge this explicitly.
- **No GC yet**: `gc_tracked` is a no-op. There is no mechanism to dispose or reclaim pull cells (Signals, Memos, HybridMemos, Relations). Only push cells (Reactive, Effect) support disposal.
- **SoA arrays are append-only for pull cells**: `pull_signals` and `pull_memos` never shrink. Disposed push cells use a free-list for slot reuse.
- **`cell_ops` shares heap references with SoA arrays**: `let ops : &CellOps = rt.pull_signals[idx]` creates a trait object reference to the same heap-allocated `PullSignalData`. Mutations through the SoA array are visible through `cell_ops`, and vice versa.

### Reasonable inferences:

- **`RuleData.input_relations` and `output_relations` are metadata-only**: They are stored but never read by any runtime logic (confirmed by compiler warnings). They likely exist for future use (rule dependency analysis, selective rule application).
- **The `HybridMemo` dirty flag is a performance optimization, not a correctness requirement**: Even without it, `pull_verify_hybrid` would still correctly verify the cell. The dirty flag provides an O(1) fast path when no push propagation has reached this cell.

### Uncertain:

- **Memory behavior under disposal**: When a `PushReactive` is disposed and its slot reused, the old `cell_ops[old_cell_id.id]` entry still points to the SoA slot (which now contains the new cell's data). Old `CellId`s from disposed cells could theoretically be used to access the new cell's data via `cell_ops`. The code does not guard against this — it relies on users not retaining stale `CellId` references. Whether this is intentional or an oversight cannot be confirmed from the code alone.
- **`Relation::insert` during non-fixpoint with prior delta facts**: If `insert` is called multiple times outside `fixpoint()`, facts accumulate in `delta`. When `fixpoint()` runs, the pre-scan at line `fixpoint.mbt:23` catches these. But if `fixpoint()` is never called, the delta facts are never drained to `current`, making `contains()` and `iter()` unable to see them. Whether this is intentional API design or a potential confusion point is unclear.

---

## 8. Key Findings

### 8.1 The Type Erasure Boundary is Cleanly Maintained

The closure-based type erasure is consistent across all cell types. The runtime never handles `T`; typed operations are always confined within closures. The `Bool` return from `compute` closures is the only information crossing the boundary, which is sufficient for the runtime to decide whether to propagate changes. This is elegant given MoonBit's lack of trait objects with associated types.

### 8.2 Short-Circuiting in `pull_verify` is Aggressive

When any dependency is found to have changed, `dep_cursor` is set to `memo.dependencies.length()`, immediately terminating the dep scan. This means verification is O(first-changed-dep) rather than O(all-deps) in the common case. Combined with the durability shortcut (which can skip entire subtrees), this makes verification sublinear in practice for graphs where changes are localized.

### 8.3 Push and Pull Coexist via Bridging

The `push_propagate_from` BFS "bridges through" pull memos and hybrid memos — it doesn't stop at them, but continues BFS through their subscribers to reach downstream push nodes. This means a push reactive can transitively depend on a pull memo that depends on a signal, and still receive eager notification. The pull memo itself is not recomputed during push propagation; it just forwards the dirty notification.

### 8.4 The Batch System Has Re-Entrant Safety

The `commit_batch` loop can process multiple waves. Callbacks from the first wave may call `signal.set()`, which (due to the temporarily elevated `batch_depth`) takes the batch path and adds to `batch_pending`. The while loop detects this and commits additional waves. This prevents unbounded recursion through `fire_on_change` -> `signal.set` -> `fire_on_change` -> ...

### 8.5 Backdating is the Central Optimization Insight

When a memo recomputes to the same value, `changed_at` is preserved. This means downstream memos comparing `dep.changed_at > memo.verified_at` see "no change" and skip their own recomputation. In a deep chain where an intermediate node recomputes to the same value, the entire downstream subtree is cut off. This is the key algorithmic insight borrowed from Salsa.

### 8.6 The Datalog Layer Integrates Cleanly but is Loosely Coupled

Relations participate in the cell system (have `CellId`, implement `CellOps`, record dependencies) but use a completely separate evaluation strategy (fixpoint, not pull-verify). The integration point is post-fixpoint: revision advance + push propagation. During fixpoint, pull verification is actively blocked (`abort` on Relation deps during `in_fixpoint`). This is a clean separation but creates a hard constraint: pull memos cannot transitively depend on relations during fixpoint evaluation.

---

## 9. What Became Clearer Through Analysis

1. **The `cell_ops` array is not just an optimization — it's a correctness enabler.** Without it, every helper function would need a `match self.cell_index[id.id]` with arms for all 7+ cell kinds. The trait-object array provides uniform dispatch while the `cell_index` array provides kind-specific access when needed (hot paths like `pull_verify`).

2. **The `PullVerifyFrame` stack in `pull_verify` serves dual purpose**: it provides iterative (non-recursive) verification AND it provides cycle path information. The `in_progress` flag on `PullMemoData` detects the cycle; the stack frames provide the path for the error message.

3. **`HybridMemo` increments `push_node_count`** (at `hybrid_memo.mbt:64`), which is what gates whether `push_propagate_from` runs at all. Without this, creating a HybridMemo would not activate push propagation from signal sets, and the dirty flag would never be set.

4. **The `staged_delta` <-> `delta` swap in `promote_staged_delta`** is a buffer-swapping technique: the old frontier's allocation is reused as the next staging buffer (then cleared). This avoids per-iteration allocation of new HashSets, which is important for fixpoint loops that may iterate many times.

5. **Subscriber link maintenance happens at two separate sites**: `Memo::force_recompute` does an inline diff using the `seen` set from `pop_tracking` (avoiding redundant HashSet construction). `Runtime::finish_tracking` does the same diff but constructs its own `old_seen`/`new_seen` sets. The duplication exists because `Memo::force_recompute` was written first and optimized; later cell types (`Reactive`, `Effect`, `HybridMemo`) use the generic `finish_tracking` helper. This is an observable code divergence, not a semantic one.
