# Layer 4a: Observer + gc() — Design Spec

**Status:** Approved — ready for implementation planning

**Date:** 2026-04-11

**Parent design:** [Dispose/GC Design Spec](../../archive/2026-04-08-dispose-gc-design.md) (sections 4-5)

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

Set to `true` at the start of `push_propagate_from`, cleared to `false` at the end. No finally/defer in MoonBit — if a user closure aborts during propagation, the flag stays true and the runtime is left inconsistent (same as existing `in_fixpoint` behavior). `gc()` checks this guard.

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
| `cells/observer.mbt` | **Create** — Observer[T] struct, get, dispose, is_disposed; Memo::observe, HybridMemo::observe, Reactive::observe; Runtime::read, read_hybrid, read_reactive |
| `cells/runtime.mbt` | `gc_root_counts` in RuntimeCore, `add_gc_root`, `remove_gc_root`, `gc`, `gc_sweep`, `collect_gc_roots`, `mark_reachable`, `cell_id_at`, `in_push_propagation` in RuntimeCore init, dispose_cell gc_root cleanup |
| `cells/push_propagate.mbt` | Set/clear `in_push_propagation` |
| `incr.mbt` | Re-export `type Observer` |
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
- manual dispose of observed cell → gc_root_counts cleaned up, observer.get aborts
- dispose observed cell then dispose observer → no gc_root_counts leak

### Integration tests (tests/)
- observe → signal.set → observer.get returns new value
- scope dispose + gc sweeps orphaned interior cells
- Runtime::read one-shot convenience
- Runtime::read on disposed memo → aborts before observe
- gc after manual dispose is safe (idempotent disposal)

### Benchmarks
- gc sweep 1k all-live
- gc sweep 1k 50%-dead
- gc sweep 1k all-dead
- observer.get warm path
- observe+dispose cycle cost

## Edge Cases

- **No `Signal::observe()` in 4a.** Sources use `signal.peek()` (Layer 5) for external reads. Sources have `gc_role() == Source` so gc() never collects them regardless — observing them has no gc() effect and no push activation story until Layer 4b. Deferring keeps the API surface minimal.
- **Observer on already-disposed cell:** The observe method checks `is_cell_disposed` and aborts — observing a dead cell is a programming error.
- **Manual dispose of an observed cell:** If a cell is manually disposed via `dispose_cell()` or `Scope::dispose()` while observers exist:
  1. `dispose_cell()` removes the cell's entry from `gc_root_counts` (if present)
  2. The Observer remains valid but stale — `Observer::get()` will abort on the disposed cell's guard
  3. `Observer::dispose()` checks `is_cell_disposed(target_id)` and skips `on_unobserve` if the target is already dead
  This prevents gc_root_counts leaks and avoids calling on_unobserve on dead cells.
- **Runtime::read() abort safety:** `read()` calls `observe → get → dispose`. The only abort scenario is reading a disposed memo, which is a programming error. `read()` adds a disposed guard before `observe()` so the root count is never incremented for a dead cell.
- **gc() is opt-in before Layer 5.** Since `.get()` is still unrestricted, interior cells may be read directly without observers. Calling gc() while holding direct references to unobserved interior cells will dispose them — this is documented behavior. Users who call gc() accept this contract.
- **gc() with empty graph:** No-op (no cells to sweep).
- **gc_root_counts HashMap memory:** Entries are removed when count reaches 0, so the map doesn't grow unbounded.
- **MemoMap interaction:** gc() may sweep memos cached in a MemoMap. `MemoMap::get()` does not yet detect disposed entries (lazy recreation deferred to Layer 4b). Until then, users should call `MemoMap::sweep()` (Layer 4b) after gc(), or avoid gc() with active MemoMaps. Document this limitation.
