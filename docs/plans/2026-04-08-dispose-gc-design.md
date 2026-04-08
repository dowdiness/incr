# Dispose/GC Design Spec

**Status:** Approved — ready for implementation planning

**Date:** 2026-04-08

## Overview

A layered dispose and garbage collection system for incr, combining insights from Jane Street Incremental (observer-rooted necessity), Preact/MobX (subscriber ref-counting), Solid.js/Leptos (scope-based ownership), and Salsa (epoch/revision-based eviction).

The design introduces three concepts: manual `dispose()` for all cell types, `Scope` for group lifecycle management, and `Observer` + `gc()` for automatic collection of unreachable interior cells.

## 1. Core Model

### Graph Boundary Principle

The incremental computation graph has an inside and an outside. Every interaction crossing this boundary requires an explicit bridge.

| Direction | Bridge | Examples |
|-----------|--------|----------|
| Outside → Inside (write) | `Signal.set()` | User provides input data |
| Inside → Outside (read) | `Observer.get()` | User reads computed results |
| Inside → Inside | `memo.get()` / `signal.get()` | Dependency tracking |

`memo.get()` only works inside a compute function (tracked context). Outside a compute function, it aborts with a message directing the user to `rt.observe()`. `signal.peek()` provides untracked reads of source cells from outside the graph.

### Three-Role Classification

| Role | Cell types | Lifecycle | Rationale |
|------|------------|-----------|-----------|
| **Source** | Signal, Relation, FunctionalRelation | User-owned. Explicitly disposed. Never auto-collected. | User creates inputs deliberately; auto-collecting would be surprising. |
| **Root** | Observer (new), Effect | User-owned. Explicitly disposed. Keeps interior subgraph alive. | Demand endpoints that define what the graph computes. |
| **Interior** | Memo, Reactive, HybridMemo | Auto-collected when unreachable from any root. Also manually disposable. | Derived computations — existence justified only by demand. |
| **Source** (Datalog) | Rule | User-owned. Explicitly disposed. Never auto-collected. | `fixpoint()` iterates all registered rules directly; GC'ing a rule silently changes fixpoint semantics. |

### API Contract

```moonbit
// Sources — write from outside, read inside
let text = Signal(rt, "hello")
text.set("world")           // write from outside: always valid
text.peek()                  // read from outside: always valid (sources never gc'd)
// Inside compute: text.get() creates tracked dependency

// Interior — graph-internal, no direct external reads
let tokens = Memo(rt, fn() { tokenize(text.get()) })
let ast = Memo(rt, fn() { parse(tokens.get()) })
// ast.get() outside compute function → aborts

// Roots — external read handles
let ast_obs = rt.observe(ast)
let tree = ast_obs.get()     // reads from outside the graph
ast_obs.dispose()            // done observing

// Side-effect roots
let eff = rt.effect(fn() { render(ast.get()) })
eff.dispose()                // stop the effect

// Testing convenience
let value = rt.read(ast)     // observe → get → dispose (one-shot)
```

## 2. Mode-Aware Observer Semantics

Observers behave differently depending on the target cell's computation mode. The user sees one API; the runtime does the right thing.

### Pull Mode (Memo)

- `observe(memo)` → increment `gc_root_counts[cell_id]` (no immediate effect — memo is already lazy)
- `observer.get()` → triggers pull_verify → recomputes if stale → returns value
- `observer.dispose()` → decrement `gc_root_counts[cell_id]`. Only when count reaches 0: remove entry (no immediate effect — deferred to gc)
- `gc()` → if memo unreachable from any root: dispose (free memory)

**Why deferred:** Pull cells compute only when demanded. An unobserved Memo wastes zero CPU — it just holds a cached value in memory. No urgency to act.

### Push Mode (Reactive)

- `observe(reactive)` → increment `gc_root_counts[cell_id]`, activate push path if suspended
- `observer.get()` → returns eagerly-computed cached value
- `observer.dispose()` → decrement `gc_root_counts[cell_id]`. Only when count reaches 0: **immediately suspend** — unsubscribe from upstream sources, decrement `push_reachable_count` on upstream cells. Push propagation no longer reaches this cell.
- `gc()` → if reactive suspended and unreachable: dispose (free memory + slot)

**Why immediate:** Push cells eagerly recompute on every input change. An unobserved Reactive wastes CPU every time any upstream signal changes. Must stop immediately.

### Hybrid Mode (HybridMemo)

- `observe(hybrid)` → increment `gc_root_counts[cell_id]`, activate push notifications if suspended
- `observer.get()` → triggers pull_verify (with push staleness hint) → returns value
- `observer.dispose()` → decrement `gc_root_counts[cell_id]`. Only when count reaches 0: **immediately suspend push path** — unsubscribe from push notifications, decrement `push_reachable_count`. Cell remains valid for pull verification (if read inside another memo's compute, pull still works). Suspension preserves `verified_at`, `changed_at`, dependency arrays, and durability metadata.
- `gc()` → if hybrid unreachable from any root: dispose (free memory)

**Why hybrid timing:** Stop the eager part immediately (prevents CPU waste). The lazy part can linger — pull verification still works until gc() collects it.

### Effect (Self-Rooting)

- Effect IS a root (self-rooting). Keeps its upstream subgraph alive.
- `effect.dispose()` → immediately stops execution, unsubscribes from sources, decrements `push_reachable_count`. Transitive deps cleaned up at next gc().

Effects are never observed — they ARE the observation.

### Summary Table

| Mode | observe() | observer.dispose() | gc() |
|------|-----------|-------------------|------|
| Pull (Memo) | Mark as root | Unmark (O(1)) | Dispose unreachable |
| Push (Reactive) | Mark + activate push | Unmark + **immediately suspend push** | Dispose suspended |
| Hybrid (HybridMemo) | Mark + activate push | Unmark + **immediately suspend push**, keep pull | Dispose unreachable |
| Effect | N/A (self-rooting) | **Immediately stop** side effect | Dispose if dead |

## 3. Composed Trait Architecture

Three focused traits, each handling one lifecycle concern. MoonBit trait composition allows keeping them small and composable.

### New Traits

```moonbit
/// How a cell responds to observer add/remove.
trait Observable {
  on_observe(Self, Runtime, CellId) -> Unit
  on_unobserve(Self, Runtime, CellId) -> Unit
}

/// How a cell cleans up its resources.
trait Disposable {
  dispose_cell(Self, Runtime, CellId) -> Unit
}

/// How gc() treats this cell.
enum GcRole { Source; Root; Interior }

trait GcParticipant {
  gc_role(Self) -> GcRole
  gc_dependencies(Self) -> Array[CellId]
}
```

### Implementations Per Cell Type

| Cell type | Observable | Disposable | GcParticipant |
|-----------|-----------|------------|---------------|
| PullSignalData | no-op / no-op | clear value, subscribers, mark Disposed, free list | `Source`, `[]` |
| MemoData (PullMemo) | no-op / no-op | clear closure, cache, deps, subscribers, upstream unsub, mark Disposed, free list | `Interior`, `self.dependencies` |
| MemoData (HybridMemo) | activate push / suspend push | clear closure, cache, deps, subscribers, push unsub, mark Disposed, free list | `Interior`, `self.dependencies` |
| PushReactiveData | activate push / suspend push | existing `dispose_reactive` logic | `Interior`, `self.sources` |
| PushEffectData | N/A | existing `dispose_effect` logic | `Root`, `self.sources` |
| RelationData | no-op / no-op | clear facts, subscribers, mark Disposed | `Source`, `[]` |
| FunctionalRelationData | no-op / no-op | clear map, subscribers, mark Disposed | `Source`, `[]` |
| RuleData | no-op / no-op | clear rule state, mark Disposed | `Source`, `self.input_relations` |

**MemoData dual role:** MemoData serves both PullMemo and HybridMemo (unified SoA entry). A `is_hybrid : Bool` flag on MemoData distinguishes them in the Observable impl, keeping the tagless final property clean (no CellRef dispatch inside a trait method).

### Parallel Dispatch Arrays

```moonbit
priv struct RuntimeCore {
  // existing
  cell_index : Array[CellRef]
  cell_ops : Array[&CellOps]

  // new — same index as cell_ops
  cell_observable : Array[&Observable]
  cell_disposable : Array[&Disposable]
  cell_gc : Array[&GcParticipant]
}
```

All five arrays share the same index (`CellId.id`). Populated together at cell creation from the same SoA data struct.

### Migration of Existing Code

Existing `Runtime::dispose_reactive`, `dispose_effect`, `dispose_hybrid_memo` methods move into `Disposable` trait impls for those cell types. This is a reorganization.

**New logic required for push/hybrid suspension:** The current dispose methods are destructive and one-way (clear slot, free list, mark Disposed). Suspension (introduced in Layer 4) is a new, reversible state machine:

- **Suspended state:** push path deactivated (unsubscribed from upstream, push_reachable_count decremented), but cell metadata preserved (verified_at, changed_at, dependencies, durability, cached value, compute closure).
- **Reactivation:** re-subscribe to upstream sources, increment push_reachable_count, force recomputation to catch up on missed changes.
- **Disposal:** permanent destruction (existing logic). Can transition from active OR suspended.

This is new logic in Layer 4, not a Layer 3 refactor. Layer 3 migrates the existing one-way dispose into `Disposable` impls. Layer 4 adds `Observable::on_observe`/`on_unobserve` with suspension support.

## 4. Observer and Scope

### Observer[T]

Observer is a lightweight keep-alive handle — NOT a cell. No SoA slot, no CellRef variant, no subscriber set.

Typed values live in the wrapper structs (`Signal[T].value`, `Memo[T].value`, etc.), not in the type-erased SoA metadata. `Observer[T]` captures a typed getter closure at creation time to bridge this gap.

```moonbit
pub struct Observer[T] {
  priv runtime : Runtime
  priv target_id : CellId
  priv getter : () -> T    // captures typed wrapper's read method
  priv mut disposed : Bool
}
```

**Creation — per-cell-type overloads:**

```moonbit
pub fn Runtime::observe[T](self : Runtime, memo : Memo[T]) -> Observer[T] {
  self.add_gc_root(memo.cell_id)
  self.core.cell_observable[memo.cell_id.id].on_observe(self, memo.cell_id)
  { runtime: self, target_id: memo.cell_id,
    getter: fn() { memo.get_observed() }, disposed: false }
}

pub fn Runtime::observe_hybrid[T](self : Runtime, h : HybridMemo[T]) -> Observer[T] {
  self.add_gc_root(h.cell_id)
  self.core.cell_observable[h.cell_id.id].on_observe(self, h.cell_id)
  { runtime: self, target_id: h.cell_id,
    getter: fn() { h.get_observed() }, disposed: false }
}

pub fn Runtime::observe_reactive[T](self : Runtime, r : Reactive[T]) -> Observer[T] {
  self.add_gc_root(r.cell_id)
  self.core.cell_observable[r.cell_id.id].on_observe(self, r.cell_id)
  { runtime: self, target_id: r.cell_id,
    getter: fn() { r.get_value() }, disposed: false }
}
```

`get_observed()` is an internal variant of `get()` that skips the tracked-context check (since Observer reads are explicitly outside the graph). It still triggers pull_verify for Memo/HybridMemo.

**Reading:**

```moonbit
pub fn Observer::get(self : Observer[T]) -> T {
  guard !self.disposed else { abort("Observer: already disposed") }
  (self.getter)()
}
```

**Disposal:**

```moonbit
pub fn Observer::dispose(self : Observer[T]) -> Unit {
  guard !self.disposed
  self.disposed = true
  let rt = self.runtime
  let id = self.target_id
  let remaining = rt.remove_gc_root(id)
  if remaining == 0 {
    rt.core.cell_observable[id.id].on_unobserve(rt, id)
  }
}
```

**One-shot convenience:**

```moonbit
pub fn Runtime::read[T](self : Runtime, memo : Memo[T]) -> T {
  let obs = self.observe(memo)
  let val = obs.get()
  obs.dispose()
  val
}
```

### gc_root_counts

```moonbit
priv struct RuntimeCore {
  // ... existing fields ...
  gc_root_counts : @hashmap.HashMap[CellId, Int]
}

fn Runtime::add_gc_root(self : Runtime, id : CellId) -> Unit {
  match self.core.gc_root_counts.get(id) {
    Some(n) => self.core.gc_root_counts.set(id, n + 1)
    None => self.core.gc_root_counts.set(id, 1)
  }
}

/// Returns remaining observer count after removal.
fn Runtime::remove_gc_root(self : Runtime, id : CellId) -> Int {
  match self.core.gc_root_counts.get(id) {
    Some(n) if n > 1 => { self.core.gc_root_counts.set(id, n - 1); n - 1 }
    Some(_) => { self.core.gc_root_counts.remove(id); 0 }
    None => 0
  }
}
```

Multiple observers on the same cell are ref-counted. `on_unobserve` is only called when the last observer for a cell is disposed (count reaches 0). This prevents premature push suspension when one observer is removed while another still exists.

### Scope

Scope owns cells and child scopes. In Layer 2, Scope provides group disposal. In Layer 4, Scope gains observer support.

```moonbit
pub struct Scope {
  priv runtime : Runtime
  priv cells : Array[CellId]
  priv children : Array[Scope]
  priv dispose_hooks : Array[() -> Unit]  // type-erased observer dispose closures (Layer 4)
  priv mut disposed : Bool
}
```

**Scoped cell constructors:** `Scope::signal()`, `Scope::memo()`, `Scope::hybrid_memo()`, `Scope::effect()` — create cells and register their IDs with the scope.

**Scoped observers (Layer 4):** `Scope::observe()` — creates an observer and registers its dispose closure with the scope.

**Nested scopes:** `Scope::child()` — creates a child scope. Disposing the parent disposes children first.

**Disposal order:** children (bottom-up) → dispose hooks (observer disposal) → owned cells.

**Idempotency:** `dispose_cell` implementations must be idempotent — disposing an already-disposed cell is a no-op (check `cell_index[id] == Disposed` before acting). This ensures scope disposal is safe even if a cell was already manually disposed.

### Scope × Observer × gc() Interaction

```
Scope owns cells     → scope.dispose() kills owned cells (immediate, explicit)
Scope owns observers → scope.dispose() removes observers (triggers on_unobserve)
gc() sweeps orphans  → collects interior cells unreachable from remaining roots
```

Typical UI component pattern:

```moonbit
let scope = Scope::new(rt)
let local_memo = scope.memo(fn() { compute_layout(ast.get()) })
let obs = scope.observe(ast)       // observe external cell

// Render: obs.get(), local_obs...

// Unmount — one call
scope.dispose()
// Next gc() pass collects newly-unreachable interior cells
```

## 5. gc() Algorithm

### Guards

gc() must only run from a "quiet" state.

```moonbit
pub fn Runtime::gc(self : Runtime) -> Unit {
  guard self.core.tracking_stack.is_empty() else {
    abort("gc: cannot run during active computation")
  }
  guard self.core.batch_depth == 0 else {
    abort("gc: cannot run during batch")
  }
  guard !self.core.in_fixpoint else {
    abort("gc: cannot run during fixpoint evaluation")
  }
  guard !self.core.in_push_propagation else {
    abort("gc: cannot run during push propagation")
  }
  self.gc_sweep()
}
```

`in_push_propagation` is a new flag set during `push_propagate_from`.

### Mark Phase

```moonbit
fn Runtime::collect_gc_roots(self : Runtime) -> Array[CellId] {
  let roots : Array[CellId] = []
  for id, _ in self.core.gc_root_counts { roots.push(id) }
  // Implicit roots: live Effects
  for i = 0; i < self.core.cell_gc.length(); i = i + 1 {
    if self.core.cell_gc[i].gc_role() == Root {
      match self.core.cell_index[i] {
        Disposed => ()
        _ => roots.push(self.cell_id_at(i))
      }
    }
  }
  roots
}

fn Runtime::mark_reachable(
  self : Runtime,
  roots : Array[CellId],
) -> @hashset.HashSet[CellId] {
  let reachable : @hashset.HashSet[CellId] = @hashset.new()
  let worklist = Array::from(roots)
  let mut wi = 0
  while wi < worklist.length() {
    let id = worklist[wi]
    wi += 1
    if reachable.contains(id) { continue }
    match self.core.cell_index[id.id] {
      Disposed => continue
      _ => ()
    }
    reachable.add(id)
    for dep in self.core.cell_gc[id.id].gc_dependencies() {
      worklist.push(dep)
    }
  }
  reachable
}
```

### Sweep Phase

```moonbit
fn Runtime::gc_sweep(self : Runtime) -> Unit {
  let roots = self.collect_gc_roots()
  let reachable = self.mark_reachable(roots)
  for i = 0; i < self.core.cell_gc.length(); i = i + 1 {
    match self.core.cell_index[i] {
      Disposed => continue
      _ => ()
    }
    if self.core.cell_gc[i].gc_role() == Interior {
      let id = self.cell_id_at(i)
      if !reachable.contains(id) {
        self.core.cell_disposable[i].dispose_cell(self, id)
      }
    }
  }
}
```

### Complexity

| Phase | Cost | Proportional to |
|-------|------|-----------------|
| Collect roots | O(gc_roots + total cells) | One pass to find Effects |
| Mark | O(live graph) | Everything reachable from roots |
| Sweep | O(total cells) | One pass through cell_index |
| **Total** | **O(total cells)** | Single linear scan dominates |

### Slot Clearing Requirements

`dispose_cell` implementations must aggressively clear all retained data to allow the host GC to collect closures and cached values:

- **PullSignalData:** clear cached value, clear subscribers, mark Disposed, add to free list
- **MemoData:** clear compute closure, clear cached value, clear dependencies array, clear subscribers, remove from upstream subscriber sets, decrement push_reachable_count (if hybrid), mark Disposed, add to free list
- **PushReactiveData/PushEffectData:** existing logic (clear_slot, free list, node_count decrement)
- **RuleData:** clear `apply_delta` closure, clear `input_relations` and `output_relations`, mark Disposed

### MemoMap Interaction

gc() does not automatically clean MemoMap entries. Two mechanisms:

1. **`MemoMap::sweep()`** — bulk removal of entries pointing to disposed memos (call after gc())
2. **Lazy recreation in `MemoMap::get()`** — detect disposed memo, remove stale entry, create fresh memo

## 6. Benchmark Plan

### Phase 1: Pre-Implementation Baselines

Run BEFORE any code changes to establish the problems GC is meant to solve.

**Cell accumulation (memory):**
- `baseline: cell count grows unbounded` — create 10k dead memos, measure cost of new memo creation in crowded runtime
- `baseline: signal.set with 10k dead memos` vs `signal.set with 0 dead memos` — measure whether dead pull cells affect signal.set cost

**Push CPU waste:**
- `baseline: push propagation with 0 reactives` — control
- `baseline: push propagation with 100 live reactives` — cost of push with live consumers
- `baseline: push propagation with 100 disposed reactives` — after manual dispose (should match 0)
- `baseline: push propagation with 100 abandoned reactives (no dispose)` — the problem case: wasted CPU

**Slot reuse:**
- `baseline: create-dispose-create cycle (reactive)` — existing free list behavior
- `baseline: memo creation (monotonic growth)` — no free list, each creation grows SoA

**Regression detection:**
- All existing benchmarks re-run to capture precise baseline numbers

### Phase 2: Post-Implementation Verification

Re-run Phase 1 benchmarks plus new benchmarks after each layer:

| After Layer | New benchmarks |
|-------------|---------------|
| Layer 1 | Memo dispose + slot reuse cycle |
| Layer 2 | Scope create/dispose cost, bulk dispose 100 cells |
| Layer 3 | Regression check for trait dispatch overhead |
| Layer 4 | gc() sweep cost (all-live, 50%-dead, all-dead), observer.get overhead, push suspension effectiveness |
| Layer 5 | All tests pass after .get() restriction migration |

### Success Criteria

| Benchmark | Target |
|-----------|--------|
| gc() sweep 10k all-live | < 1ms |
| gc() sweep 10k all-dead | < 2ms |
| Push propagation with suspended reactives | Same as 0-reactive baseline |
| observer.get() warm | Within 10% of memo.get() warm |
| observe+dispose cycle | < 1μs |
| All existing benchmarks | No regression > 5% |

### Benchmark-Driven Decisions

If pre-implementation baselines show no measurable CPU waste from abandoned push cells, immediate suspension (the most complex part of the design) may not be worth implementing. Benchmarks drive the decision.

## 7. Layered Delivery

### Layer 1: Manual Dispose for All Cell Types

Complete `dispose()` for Signal, Memo, Relation, Rule, FunctionalRelation. Add free lists for pull cell SoA slots. Add `is_disposed()` and disposed guards on `.get()`.

**Depends on:** Nothing.

### Layer 2: Scope (cell ownership only)

`Scope` struct with scoped cell constructors, nested scopes, recursive dispose. Owns cells only — no observer support yet (that arrives in Layer 4 via `Scope::observe()`).

**Depends on:** Layer 1.

### Layer 3: Composed Traits

`Observable`, `Disposable`, `GcParticipant` traits. Parallel dispatch arrays. Migrate existing dispose methods into trait impls. Add `is_hybrid` flag to MemoData.

**Depends on:** Layer 1.

### Layer 4: Observer + gc()

`Observer[T]` type with typed getter closure, `gc_root_counts` on RuntimeCore, `Runtime::gc()` with mark-and-sweep, `Runtime::read()` convenience, `MemoMap::sweep()`, `in_push_propagation` guard flag, push/hybrid suspension state machine in `Observable` impls, `Scope::observe()` (adds observer support to Layer 2 Scope).

**Depends on:** Layers 2 and 3.

### Layer 5: API Boundary Enforcement

Restrict `memo.get()`, `hybrid_memo.get()`, `reactive.get()` to tracked context only. Add `signal.peek()`. Migrate all tests and benchmarks to use `rt.read()` or observers.

**Depends on:** Layer 4.

### Delivery Summary

```
Layer 1: Manual dispose     ← foundation, immediate value
  ↓
Layer 2: Scope              ← UI lifecycle, builds on dispose
  ↓
Layer 3: Composed traits    ← architecture, enables extensibility
  ↓
Layer 4: Observer + gc()    ← automatic collection, the main feature
  ↓
Layer 5: API boundary       ← clean contract, breaking change (last)
```

Each layer is shippable independently. Layer 5 is the only breaking change.

## 8. Edge Cases and Safety Rules

### dispose() During Active Computation

Manual `dispose()` and `scope.dispose()` must respect the same guards as gc():

- **During pull_verify:** Forbidden. A cell being verified is on the tracking stack; disposing it would corrupt the verify loop. `dispose()` aborts if the cell's CellId is in the active tracking stack.
- **During push propagation:** Safe. Existing behavior: `push_propagate_from` skips Disposed entries in the BFS queue. No change needed.
- **During batch:** Disposing a Signal mid-batch discards its pending write from `batch_pending`. The implementation must clear `pending_value` and remove the signal's commit object from the batch queue.
- **During fixpoint:** Forbidden (same as gc).

### Idempotent Disposal

All `dispose_cell` implementations must be idempotent: check `cell_index[id] == Disposed` and return early if so. This ensures:
- Scope disposing a cell that was already manually disposed is a no-op
- gc() after manual dispose skips already-disposed cells
- Double-dispose from any path is safe

### Closure-Captured Handles

A memo's compute closure may capture a reference to a cell that later gets GC'd. Closure capture does NOT count as reachability — tracing into arbitrary user closures is infeasible with SoA storage. When the compute function runs and reads the captured handle via `.get()`, it hits the Disposed guard and aborts. This is documented behavior: **compute closures must not capture handles to cells outside their reachability subgraph.**

### TrackedCell

`TrackedCell[T]` is a thin wrapper around `Signal[T]` (tracked_cell.mbt:16). It inherits Signal's lifecycle:
- Classified as **Source** (never auto-collected)
- `TrackedCell::dispose()` delegates to `Signal::dispose()` on the inner signal
- `TrackedCell::peek()` delegates to `Signal::peek()` on the inner signal
- `TrackedCell::is_disposed()` delegates to `Signal::is_disposed()`

### gc_tracked and Trackable

The existing `gc_tracked()` stub (traits.mbt:250) and `Trackable` trait are redesigned:
- `gc_tracked` is deprecated in favor of Scope-based ownership
- `Trackable::cell_ids()` is repurposed: used by `Scope::add_tracked()` to register all of a struct's TrackedCells with a scope for bulk lifecycle management
- The original intent ("mark as GC roots") conflicted with the traversal direction — TrackedCells are Sources with no downstream dependency edges, so marking them as roots keeps nothing alive

```moonbit
pub fn Scope::add_tracked[T : Trackable](self : Scope, tracked : T) -> Unit {
  for id in tracked.cell_ids() {
    self.cells.push(id)
  }
}
```

## Literature References

This design draws from:

- **Jane Street Incremental** — observer-rooted necessity, necessary/unnecessary node states
- **Salsa** — revision-based staleness, durability-aware GC, LRU eviction
- **Preact Signals / MobX** — subscriber ref-counting, auto-suspend on unwatched
- **Solid.js / Leptos** — scope-based ownership, hierarchical cleanup
- **Adapton** — demanded computation graph, no explicit GC (the baseline we're improving on)
- **Skip** — dependency coarsening (considered, deferred as impractical at library level)
- **Self-Adjusting Computation (Acar et al.)** — GC cost warning (up to 67% of execution time)
- **Hammer & Acar (ISMM 2008)** — O(1) amortized reclamation for trace elements
- **"Build Systems à la Carte"** — scheduler/rebuilder taxonomy (GC is orthogonal to both)
- **TC39 Signals Proposal** — WeakRef-based GC for computed signals (not applicable to SoA)
