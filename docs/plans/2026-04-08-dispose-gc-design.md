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
| **Interior** | Memo, Reactive, HybridMemo, Rule | Auto-collected when unreachable from any root. Also manually disposable. | Derived computations — existence justified only by demand. |

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

- `observe(memo)` → add to gc_roots (no immediate effect — memo is already lazy)
- `observer.get()` → triggers pull_verify → recomputes if stale → returns value
- `observer.dispose()` → remove from gc_roots (no immediate effect — deferred to gc)
- `gc()` → if memo unreachable from any root: dispose (free memory)

**Why deferred:** Pull cells compute only when demanded. An unobserved Memo wastes zero CPU — it just holds a cached value in memory. No urgency to act.

### Push Mode (Reactive)

- `observe(reactive)` → add to gc_roots, activate push path if suspended
- `observer.get()` → returns eagerly-computed cached value
- `observer.dispose()` → remove from gc_roots. If no remaining roots: **immediately suspend** — unsubscribe from upstream sources, decrement `push_reachable_count` on upstream cells. Push propagation no longer reaches this cell.
- `gc()` → if reactive suspended and unreachable: dispose (free memory + slot)

**Why immediate:** Push cells eagerly recompute on every input change. An unobserved Reactive wastes CPU every time any upstream signal changes. Must stop immediately.

### Hybrid Mode (HybridMemo)

- `observe(hybrid)` → add to gc_roots, activate push notifications if suspended
- `observer.get()` → triggers pull_verify (with push staleness hint) → returns value
- `observer.dispose()` → remove from gc_roots. If no remaining roots: **immediately suspend push path** — unsubscribe from push notifications, decrement `push_reachable_count`. Cell remains valid for pull verification (if read inside another memo's compute, pull still works).
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
| RuleData | no-op / no-op | clear rule state, mark Disposed | `Interior`, `self.relation_deps` |

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

Existing `Runtime::dispose_reactive`, `dispose_effect`, `dispose_hybrid_memo` methods move into `Disposable` trait impls. No logic changes — reorganization only.

## 4. Observer and Scope

### Observer[T]

Observer is a lightweight keep-alive handle — NOT a cell. No SoA slot, no CellRef variant, no subscriber set.

```moonbit
pub struct Observer[T] {
  priv runtime : Runtime
  priv target_id : CellId
  priv mut disposed : Bool
}
```

**Creation:**

```moonbit
pub fn Runtime::observe[T](self : Runtime, memo : Memo[T]) -> Observer[T] {
  self.gc_roots.add(memo.cell_id)
  self.core.cell_observable[memo.cell_id.id].on_observe(self, memo.cell_id)
  { runtime: self, target_id: memo.cell_id, disposed: false }
}
```

**Reading:**

```moonbit
pub fn Observer::get(self : Observer[T]) -> T {
  guard !self.disposed else { abort("Observer: already disposed") }
  self.runtime.read_cell(self.target_id)
}
```

**Disposal:**

```moonbit
pub fn Observer::dispose(self : Observer[T]) -> Unit {
  guard !self.disposed
  self.disposed = true
  self.runtime.gc_roots.remove(self.target_id)
  self.runtime.core.cell_observable[self.target_id.id]
    .on_unobserve(self.runtime, self.target_id)
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

### gc_roots

```moonbit
priv struct RuntimeCore {
  // ... existing fields ...
  gc_roots : @hashset.HashSet[CellId]
}
```

### Scope

Scope owns cells, observers, and child scopes. Disposing the scope recursively disposes everything.

```moonbit
pub struct Scope {
  priv runtime : Runtime
  priv cells : Array[CellId]
  priv observer_targets : Array[CellId]  // target cell IDs of owned observers
  priv children : Array[Scope]
  priv mut disposed : Bool
}
```

**Scoped cell constructors:** `Scope::signal()`, `Scope::memo()`, `Scope::hybrid_memo()`, `Scope::effect()` — create cells and register their IDs with the scope.

**Scoped observers:** `Scope::observe()` — creates an observer and registers it with the scope.

**Nested scopes:** `Scope::child()` — creates a child scope. Disposing the parent disposes children first.

**Disposal order:** children (bottom-up) → observers (remove from gc_roots, call on_unobserve) → owned cells.

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
  for id in self.core.gc_roots { roots.push(id) }
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
- **RuleData:** clear rule closure, clear relation deps, mark Disposed

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

### Layer 2: Scope

`Scope` struct with scoped cell constructors, nested scopes, recursive dispose.

**Depends on:** Layer 1.

### Layer 3: Composed Traits

`Observable`, `Disposable`, `GcParticipant` traits. Parallel dispatch arrays. Migrate existing dispose methods into trait impls. Add `is_hybrid` flag to MemoData.

**Depends on:** Layer 1.

### Layer 4: Observer + gc()

`Observer[T]` type, `gc_roots` on RuntimeCore, `Runtime::gc()` with mark-and-sweep, `Runtime::read()` convenience, `MemoMap::sweep()`, `in_push_propagation` guard flag. `Scope::observe()`.

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
