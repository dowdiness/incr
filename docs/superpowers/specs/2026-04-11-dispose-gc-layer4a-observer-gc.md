# Layer 4a: Observer + gc() — Design Spec

**Status:** Approved — ready for implementation planning

**Date:** 2026-04-11

**Parent design:** [Dispose/GC Design Spec](../../plans/2026-04-08-dispose-gc-design.md) (sections 4-5)

## Goal

Add Observer[T] (typed keep-alive handle for reading computed values from outside the graph) and Runtime::gc() (mark-and-sweep collection of unreachable interior cells). This is the core GC mechanism without push suspension — `on_observe`/`on_unobserve` remain no-ops.

## Scope

**In scope (Layer 4a):**
- `Observer[T]` struct in `cells/observer.mbt`
- `Memo::observe()`, `HybridMemo::observe()`, `Reactive::observe()` creation methods
- `Observer::get()`, `Observer::dispose()`, `Observer::is_disposed()`
- `gc_root_counts : @hashmap.HashMap[CellId, Int]` on RuntimeCore
- `Runtime::add_gc_root()`, `Runtime::remove_gc_root()` helpers
- `Runtime::gc()` with guards + mark-and-sweep
- `in_push_propagation : Bool` flag on RuntimeCore
- `Runtime::read()` one-shot convenience (+ `read_hybrid`, `read_reactive`)
- `cell_id_at(i)` helper for index-to-CellId reconstruction
- Re-export `Observer[T]` from root `incr.mbt`
- Unit tests and integration tests

**Out of scope (Layer 4b):**
- `on_observe`/`on_unobserve` real implementations (push activation/suspension)
- `Scope::observe()` (observer lifecycle via dispose hooks)
- `MemoMap::sweep()`

## Observer[T]

Lightweight keep-alive handle — NOT a cell. No SoA slot, no CellRef variant.

```moonbit
pub struct Observer[T] {
  priv runtime : Runtime
  priv target_id : CellId
  priv getter : () -> T
  priv mut disposed : Bool

  fn new(...) -> Observer[T]  // custom constructor
}
```

### Creation — methods on cell types

Each cell type provides an `observe()` method that:
1. Increments gc_root_counts for the target cell
2. Calls `on_observe` via cell_lifecycle (no-op in 4a)
3. Returns an Observer with a getter closure capturing the cell's `.get()` method

```moonbit
pub fn Memo::observe(self : Memo[T]) -> Observer[T]
pub fn HybridMemo::observe(self : HybridMemo[T]) -> Observer[T]
pub fn Reactive::observe(self : Reactive[T]) -> Observer[T]
```

The getter captures existing `.get()` — outside tracked context, dependency recording is a no-op. Layer 5 will switch to an internal `get_observed()` variant when `.get()` gets restricted.

### Reading and disposal

```moonbit
pub fn Observer::get(self : Observer[T]) -> T
  // guard !self.disposed else abort
  // call getter

pub fn Observer::dispose(self : Observer[T]) -> Unit
  // guard !self.disposed (idempotent)
  // set disposed = true
  // decrement gc_root_counts
  // if remaining == 0: call on_unobserve via cell_lifecycle (no-op in 4a)

pub fn Observer::is_disposed(self : Observer[T]) -> Bool
```

### One-shot convenience

```moonbit
pub fn Runtime::read[T](self : Runtime, memo : Memo[T]) -> T
  // observe → get → dispose

pub fn Runtime::read_hybrid[T](self : Runtime, h : HybridMemo[T]) -> T
pub fn Runtime::read_reactive[T](self : Runtime, r : Reactive[T]) -> T
```

## gc_root_counts

Added to RuntimeCore:

```moonbit
gc_root_counts : @hashmap.HashMap[CellId, Int]
```

Helpers:

```moonbit
fn Runtime::add_gc_root(self : Runtime, id : CellId) -> Unit
  // increment existing or insert 1

fn Runtime::remove_gc_root(self : Runtime, id : CellId) -> Int
  // decrement, remove at 0, return remaining count
```

Multiple observers on the same cell are ref-counted. `on_unobserve` fires only when the last observer is disposed (count reaches 0).

## in_push_propagation guard

Added to RuntimeCore:

```moonbit
mut in_push_propagation : Bool
```

Set to `true` at the start of `push_propagate_from`, cleared to `false` at the end (in a finally-like pattern to handle aborts). `gc()` checks this guard.

## Runtime::gc()

### Guards

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

### Algorithm

1. **Collect roots:** gc_root_counts keys + Effects (cells where `cell_ops[i].gc_role() == Root` and not Disposed)
2. **Mark reachable:** BFS from roots following `cell_ops[id].gc_dependencies()`
3. **Sweep:** For each non-Disposed cell where `cell_ops[i].gc_role() == Interior` and not in reachable set: call `self.dispose_cell(id)`

### Helper

```moonbit
fn Runtime::cell_id_at(self : Runtime, i : Int) -> CellId {
  { runtime_id: self.core.runtime_id, id: i }
}
```

## Files

| File | Change |
|------|--------|
| `cells/observer.mbt` | **Create** — Observer[T] struct, get, dispose, is_disposed |
| `cells/memo.mbt` | Add `Memo::observe` |
| `cells/hybrid_memo.mbt` | Add `HybridMemo::observe` |
| `cells/push_reactive.mbt` | Add `Reactive::observe` |
| `cells/runtime.mbt` | `gc_root_counts` in RuntimeCore, `add_gc_root`, `remove_gc_root`, `gc`, `gc_sweep`, `collect_gc_roots`, `mark_reachable`, `cell_id_at`, `in_push_propagation` in RuntimeCore init |
| `cells/push_propagate.mbt` | Set/clear `in_push_propagation` |
| `incr.mbt` | Re-export `type Observer` |
| `traits.mbt` | `Runtime::read`, `Runtime::read_hybrid`, `Runtime::read_reactive` |
| `cells/observer_test.mbt` | **Create** — unit tests for Observer |
| `cells/gc_test.mbt` | **Create** — unit tests for gc() |
| `tests/observer_test.mbt` | **Create** — integration tests |
| `tests/gc_test.mbt` | **Create** — integration tests |
| `tests/bench_test.mbt` | gc() benchmarks |

## Testing Strategy

### Observer unit tests (cells/observer_test.mbt)
- observe memo → get returns computed value
- observe hybrid_memo → get returns computed value
- observe reactive → get returns current value
- dispose observer → is_disposed returns true
- get after dispose → aborts
- multiple observers on same cell → ref-counted
- dispose one of multiple observers → other still works
- observe disposed cell → aborts (guard in observe method)

### gc() unit tests (cells/gc_test.mbt)
- gc with no observers → disposes all interior cells
- gc with observer on memo → keeps memo and its deps alive
- gc with observer on memo → disposes unreachable memos
- gc after observer dispose → sweeps newly-unreachable cells
- gc keeps effects alive (self-rooting)
- gc skips sources (never collected)
- gc during batch → aborts
- gc during fixpoint → aborts
- gc during push propagation → aborts
- gc during active computation → aborts
- gc is idempotent (running twice is safe)
- diamond dependency: gc keeps shared deps alive when one path is observed

### Integration tests (tests/)
- observe → signal.set → observer.get returns new value
- scope dispose + gc sweeps orphaned interior cells
- Runtime::read one-shot convenience
- gc after manual dispose is safe (idempotent disposal)

### Benchmarks
- gc sweep 1k all-live
- gc sweep 1k 50%-dead
- gc sweep 1k all-dead
- observer.get warm path
- observe+dispose cycle cost

## Edge Cases

- **Observer on Source cell:** Sources have `gc_role() == Source` so gc() never collects them regardless of observer count. Observing a signal is valid (for Layer 4b push activation) but has no gc() effect.
- **Observer on already-disposed cell:** The observe method should check `is_cell_disposed` and abort — observing a dead cell is a programming error.
- **gc() with empty graph:** No-op (no cells to sweep).
- **gc_root_counts HashMap memory:** Entries are removed when count reaches 0, so the map doesn't grow unbounded.
