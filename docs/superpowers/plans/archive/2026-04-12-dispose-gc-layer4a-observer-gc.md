# Layer 4a: Observer + gc() Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Add Observer[T] (typed keep-alive handle for reading computed values from outside the graph) and Runtime::gc() (mark-and-sweep collection of unreachable interior cells).

**Architecture:** Observer[T] is a lightweight handle (not a cell) that ref-counts gc_root_counts entries. gc() marks cells reachable from gc_root_counts + Effects, then sweeps unreachable Interior cells via dispose_cell. in_push_propagation guard prevents gc() during push propagation.

**Tech Stack:** MoonBit, existing incr library (cells/, types/, root package)

---

## File Structure

| File | Responsibility |
|------|---------------|
| `cells/observer.mbt` | **Create** — Observer[T] struct, get, dispose, is_disposed |
| `cells/runtime.mbt` | gc_root_counts in RuntimeCore, add/remove_gc_root, gc(), gc_sweep, collect_gc_roots, mark_reachable, cell_id_at, in_push_propagation flag, dispose_cell gc_root cleanup |
| `cells/push_propagate.mbt` | Set/clear in_push_propagation around push_propagate_from |
| `cells/memo.mbt` | Add Memo::observe |
| `cells/hybrid_memo.mbt` | Add HybridMemo::observe |
| `cells/push_reactive.mbt` | Add Reactive::observe |
| `incr.mbt` | Re-export type Observer |
| `traits.mbt` | Runtime::read, Runtime::read_hybrid, Runtime::read_reactive |
| `cells/observer_test.mbt` | **Create** — Observer unit tests |
| `cells/gc_test.mbt` | **Create** — gc() unit tests |
| `cells/gc_wbtest.mbt` | **Create** — gc() whitebox tests (gc_root_counts internals) |
| `tests/observer_test.mbt` | **Create** — Observer integration tests |
| `tests/gc_test.mbt` | **Create** — gc() integration tests |
| `tests/bench_test.mbt` | Layer 4a benchmarks |

---

### Task 1: RuntimeCore infrastructure — gc_root_counts, in_push_propagation, cell_id_at

**Files:**
- Modify: `cells/runtime.mbt` (RuntimeCore struct + Runtime::new + new helpers)
- Modify: `cells/push_propagate.mbt` (set/clear flag)
- Test: `cells/gc_wbtest.mbt`

- [ ] **Step 1: Write whitebox tests for gc_root_counts helpers**

Create `cells/gc_wbtest.mbt`:

```moonbit
///|
test "add_gc_root: inserts new entry with count 1" {
  let rt = Runtime::new()
  let sig = Signal::new(rt, 42)
  rt.add_gc_root(sig.id())
  inspect(rt.core.gc_root_counts.get(sig.id()), content="Some(1)")
}

///|
test "add_gc_root: increments existing entry" {
  let rt = Runtime::new()
  let sig = Signal::new(rt, 42)
  rt.add_gc_root(sig.id())
  rt.add_gc_root(sig.id())
  inspect(rt.core.gc_root_counts.get(sig.id()), content="Some(2)")
}

///|
test "remove_gc_root: decrements and returns remaining" {
  let rt = Runtime::new()
  let sig = Signal::new(rt, 42)
  rt.add_gc_root(sig.id())
  rt.add_gc_root(sig.id())
  let remaining = rt.remove_gc_root(sig.id())
  inspect(remaining, content="1")
  inspect(rt.core.gc_root_counts.get(sig.id()), content="Some(1)")
}

///|
test "remove_gc_root: removes entry at zero" {
  let rt = Runtime::new()
  let sig = Signal::new(rt, 42)
  rt.add_gc_root(sig.id())
  let remaining = rt.remove_gc_root(sig.id())
  inspect(remaining, content="0")
  inspect(rt.core.gc_root_counts.get(sig.id()), content="None")
}

///|
test "remove_gc_root: returns 0 for unknown cell" {
  let rt = Runtime::new()
  let sig = Signal::new(rt, 42)
  let remaining = rt.remove_gc_root(sig.id())
  inspect(remaining, content="0")
}

///|
test "cell_id_at: reconstructs CellId from index" {
  let rt = Runtime::new()
  let sig = Signal::new(rt, 42)
  let reconstructed = rt.cell_id_at(sig.id().id)
  inspect(reconstructed == sig.id(), content="true")
}

///|
test "in_push_propagation: false by default" {
  let rt = Runtime::new()
  inspect(rt.core.in_push_propagation, content="false")
}
```

- [ ] **Step 2: Run tests to verify they fail**

Run: `moon test -p dowdiness/incr/cells -f gc_wbtest.mbt`
Expected: FAIL — `gc_root_counts`, `add_gc_root`, `remove_gc_root`, `cell_id_at`, `in_push_propagation` do not exist

- [ ] **Step 3: Add gc_root_counts and in_push_propagation to RuntimeCore**

In `cells/runtime.mbt`, add two fields to `RuntimeCore` after `mut in_fixpoint : Bool`:

```moonbit
  /// Reference counts for observed cells. Key = observed CellId,
  /// value = number of live Observer handles. on_unobserve fires only
  /// when count reaches 0.
  gc_root_counts : @hashmap.HashMap[CellId, Int]
  /// True while push_propagate_from is running. Guards gc() from
  /// running during push propagation.
  mut in_push_propagation : Bool
```

In `Runtime::new`, add initializers to the `core` literal after `in_fixpoint: false`:

```moonbit
      gc_root_counts: @hashmap.new(),
      in_push_propagation: false,
```

- [ ] **Step 4: Add add_gc_root, remove_gc_root, cell_id_at helpers**

In `cells/runtime.mbt`, add after the `dispose_cell` method:

```moonbit
///|
/// Increments the observer reference count for a cell.
fn Runtime::add_gc_root(self : Runtime, id : CellId) -> Unit {
  match self.core.gc_root_counts.get(id) {
    Some(n) => self.core.gc_root_counts.set(id, n + 1)
    None => self.core.gc_root_counts.set(id, 1)
  }
}

///|
/// Decrements the observer reference count for a cell.
/// Removes the entry when count reaches 0. Returns remaining count.
fn Runtime::remove_gc_root(self : Runtime, id : CellId) -> Int {
  match self.core.gc_root_counts.get(id) {
    Some(n) if n > 1 => {
      self.core.gc_root_counts.set(id, n - 1)
      n - 1
    }
    Some(_) => {
      self.core.gc_root_counts.remove(id)
      0
    }
    None => 0
  }
}

///|
/// Reconstructs a CellId from a cell_ops array index.
fn Runtime::cell_id_at(self : Runtime, i : Int) -> CellId {
  { runtime_id: self.core.runtime_id, id: i }
}
```

- [ ] **Step 5: Set/clear in_push_propagation in push_propagate_from**

In `cells/push_propagate.mbt`, in `Runtime::push_propagate_from`, add at the very start of the function body (before `let update_queue`):

```moonbit
  self.core.in_push_propagation = true
```

And at the very end of the function body (after the `while !update_queue.is_empty()` loop closes):

```moonbit
  self.core.in_push_propagation = false
```

- [ ] **Step 6: Run tests to verify they pass**

Run: `moon test -p dowdiness/incr/cells -f gc_wbtest.mbt`
Expected: PASS (7 tests)

- [ ] **Step 7: Run full test suite for regressions**

Run: `moon test`
Expected: All tests pass

- [ ] **Step 8: Commit**

```bash
git add cells/runtime.mbt cells/push_propagate.mbt cells/gc_wbtest.mbt
git commit -m "feat: add gc_root_counts, in_push_propagation, and cell_id_at to RuntimeCore"
```

---

### Task 2: Observer[T] struct — creation, get, dispose

**Files:**
- Create: `cells/observer.mbt`
- Create: `cells/observer_test.mbt`

- [ ] **Step 1: Write unit tests for Observer**

Create `cells/observer_test.mbt`:

```moonbit
///|
test "observer: memo observe and get" {
  let rt = Runtime::new()
  let sig = Signal::new(rt, 10)
  let m = Memo::new(rt, fn() { sig.get() * 2 })
  let obs = m.observe()
  inspect(obs.get(), content="20")
  obs.dispose()
}

///|
test "observer: hybrid_memo observe and get" {
  let rt = Runtime::new()
  let sig = Signal::new(rt, 5)
  let h = HybridMemo::new(rt, fn() { sig.get() + 1 })
  let obs = h.observe()
  inspect(obs.get(), content="6")
  obs.dispose()
}

///|
test "observer: reactive observe and get" {
  let rt = Runtime::new()
  let sig = Signal::new(rt, 3)
  let r = Reactive::new(rt, fn() { sig.get() * 3 })
  let obs = r.observe()
  inspect(obs.get(), content="9")
  obs.dispose()
}

///|
test "observer: dispose sets is_disposed" {
  let rt = Runtime::new()
  let sig = Signal::new(rt, 1)
  let m = Memo::new(rt, fn() { sig.get() })
  let obs = m.observe()
  inspect(obs.is_disposed(), content="false")
  obs.dispose()
  inspect(obs.is_disposed(), content="true")
}

///|
test "observer: dispose is idempotent" {
  let rt = Runtime::new()
  let sig = Signal::new(rt, 1)
  let m = Memo::new(rt, fn() { sig.get() })
  let obs = m.observe()
  obs.dispose()
  obs.dispose() // no abort
  inspect(obs.is_disposed(), content="true")
}

///|
test "panic observer: get after dispose aborts" {
  let rt = Runtime::new()
  let sig = Signal::new(rt, 1)
  let m = Memo::new(rt, fn() { sig.get() })
  let obs = m.observe()
  obs.dispose()
  ignore(obs.get())
}

///|
test "observer: multiple observers on same cell are ref-counted" {
  let rt = Runtime::new()
  let sig = Signal::new(rt, 1)
  let m = Memo::new(rt, fn() { sig.get() })
  let obs1 = m.observe()
  let obs2 = m.observe()
  inspect(obs1.get(), content="1")
  inspect(obs2.get(), content="1")
  obs1.dispose()
  // obs2 still works
  inspect(obs2.get(), content="1")
  obs2.dispose()
}

///|
test "panic observer: observe disposed memo aborts" {
  let rt = Runtime::new()
  let sig = Signal::new(rt, 1)
  let m = Memo::new(rt, fn() { sig.get() })
  m.dispose()
  ignore(m.observe())
}
```

- [ ] **Step 2: Run tests to verify they fail**

Run: `moon test -p dowdiness/incr/cells -f observer_test.mbt`
Expected: FAIL — `observe`, `Observer` do not exist

- [ ] **Step 3: Create Observer[T] struct and implement observe methods**

Create `cells/observer.mbt`:

```moonbit
///|
/// A typed keep-alive handle for reading computed values from outside the
/// dependency graph.
///
/// Observer is NOT a cell — it has no SoA slot, no CellRef variant, and
/// no subscriber set. It is a lightweight ref-counted handle that:
/// 1. Increments gc_root_counts for the target cell (keeps it alive during gc)
/// 2. Provides a typed getter for reading the cell's value
/// 3. Decrements gc_root_counts on dispose (allows gc to collect)
///
/// # Example
///
/// ```moonbit nocheck
/// let rt = Runtime()
/// let sig = Signal(rt, 10)
/// let m = Memo(rt, fn() { sig.get() * 2 })
/// let obs = m.observe()
/// inspect(obs.get(), content="20")
/// sig.set(15)
/// inspect(obs.get(), content="30")
/// obs.dispose()
/// ```
pub struct Observer[T] {
  priv runtime : Runtime
  priv target_id : CellId
  priv getter : () -> T
  priv mut disposed : Bool
} derive(Debug(ignore=[Runtime, Fn, CellId]))

///|
/// Returns the current value of the observed cell.
///
/// For Memo and HybridMemo targets, this triggers pull verification
/// if the cell is stale. For Reactive targets, returns the eagerly
/// computed cached value.
///
/// # Panics
///
/// Aborts if the observer has been disposed.
pub fn[T] Observer::get(self : Observer[T]) -> T {
  guard !self.disposed else { abort("Observer: already disposed") }
  (self.getter)()
}

///|
/// Releases this observer's keep-alive hold on the target cell.
///
/// Decrements gc_root_counts. When the last observer for a cell is
/// disposed (count reaches 0), calls on_unobserve via CellLifecycle
/// (no-op in Layer 4a; Layer 4b adds push suspension).
///
/// Idempotent: disposing an already-disposed observer is a no-op.
pub fn[T] Observer::dispose(self : Observer[T]) -> Unit {
  guard !self.disposed
  self.disposed = true
  let rt = self.runtime
  let id = self.target_id
  // Skip on_unobserve if target was already manually disposed
  if rt.is_cell_disposed(id) {
    rt.core.gc_root_counts.remove(id)
    return
  }
  let remaining = rt.remove_gc_root(id)
  if remaining == 0 {
    rt.core.cell_lifecycle[id.id].on_unobserve(rt, id)
  }
}

///|
/// Returns true if this observer has been disposed.
pub fn[T] Observer::is_disposed(self : Observer[T]) -> Bool {
  self.disposed
}

///|
/// Creates an observer for a Memo cell.
///
/// Increments gc_root_counts and calls on_observe (no-op in Layer 4a).
/// The getter captures the memo's `.get()` method.
///
/// # Panics
///
/// Aborts if the memo has been disposed.
pub fn[T] Memo::observe(self : Memo[T]) -> Observer[T] {
  guard !self.rt.is_cell_disposed(self.cell_id) else {
    abort("Memo::observe called on a disposed memo")
  }
  let rt = self.rt
  rt.add_gc_root(self.cell_id)
  rt.core.cell_lifecycle[self.cell_id.id].on_observe(rt, self.cell_id)
  { runtime: rt, target_id: self.cell_id, getter: fn() { self.get() }, disposed: false }
}

///|
/// Creates an observer for a HybridMemo cell.
///
/// # Panics
///
/// Aborts if the hybrid memo has been disposed.
pub fn[T : Eq] HybridMemo::observe(self : HybridMemo[T]) -> Observer[T] {
  guard !self.rt.is_cell_disposed(self.cell_id) else {
    abort("HybridMemo::observe called on a disposed hybrid memo")
  }
  let rt = self.rt
  rt.add_gc_root(self.cell_id)
  rt.core.cell_lifecycle[self.cell_id.id].on_observe(rt, self.cell_id)
  { runtime: rt, target_id: self.cell_id, getter: fn() { self.get() }, disposed: false }
}

///|
/// Creates an observer for a Reactive cell.
///
/// # Panics
///
/// Aborts if the reactive has been disposed.
pub fn[T] Reactive::observe(self : Reactive[T]) -> Observer[T] {
  let cell_id = self.cell_id.id
  guard !self.rt.is_cell_disposed(cell_id) else {
    abort("Reactive::observe called on a disposed reactive")
  }
  let rt = self.rt
  rt.add_gc_root(cell_id)
  rt.core.cell_lifecycle[cell_id.id].on_observe(rt, cell_id)
  { runtime: rt, target_id: cell_id, getter: fn() { self.get() }, disposed: false }
}
```

- [ ] **Step 4: Run tests to verify they pass**

Run: `moon test -p dowdiness/incr/cells -f observer_test.mbt`
Expected: PASS (8 tests)

- [ ] **Step 5: Run full test suite for regressions**

Run: `moon test`
Expected: All tests pass

- [ ] **Step 6: Commit**

```bash
git add cells/observer.mbt cells/observer_test.mbt
git commit -m "feat: add Observer[T] with observe methods on Memo, HybridMemo, Reactive"
```

---

### Task 3: Re-export Observer + add Runtime::read convenience

**Files:**
- Modify: `incr.mbt`
- Modify: `traits.mbt`
- Test: `tests/observer_test.mbt`

- [ ] **Step 1: Write integration tests**

Create `tests/observer_test.mbt`:

```moonbit
///|
test "observer: observe through public API" {
  let rt = @incr.Runtime()
  let sig = @incr.Signal(rt, 10)
  let m = @incr.Memo(rt, fn() { sig.get() * 2 })
  let obs = m.observe()
  inspect(obs.get(), content="20")
  obs.dispose()
}

///|
test "observer: signal.set updates observer.get" {
  let rt = @incr.Runtime()
  let sig = @incr.Signal(rt, 5)
  let m = @incr.Memo(rt, fn() { sig.get() + 1 })
  let obs = m.observe()
  inspect(obs.get(), content="6")
  sig.set(10)
  inspect(obs.get(), content="11")
  obs.dispose()
}

///|
test "runtime: read one-shot convenience" {
  let rt = @incr.Runtime()
  let sig = @incr.Signal(rt, 7)
  let m = @incr.Memo(rt, fn() { sig.get() * 3 })
  inspect(rt.read(m), content="21")
}

///|
test "runtime: read_hybrid one-shot convenience" {
  let rt = @incr.Runtime()
  let sig = @incr.Signal(rt, 4)
  let h = @incr.HybridMemo(rt, fn() { sig.get() + 2 })
  inspect(rt.read_hybrid(h), content="6")
}

///|
test "runtime: read_reactive one-shot convenience" {
  let rt = @incr.Runtime()
  let sig = @incr.Signal(rt, 3)
  let r = @incr.Reactive(rt, fn() { sig.get() * 5 })
  inspect(rt.read_reactive(r), content="15")
}

///|
test "panic runtime: read on disposed memo aborts" {
  let rt = @incr.Runtime()
  let sig = @incr.Signal(rt, 1)
  let m = @incr.Memo(rt, fn() { sig.get() })
  m.dispose()
  ignore(rt.read(m))
}
```

- [ ] **Step 2: Run tests to verify they fail**

Run: `moon test -p dowdiness/incr/tests -f observer_test.mbt`
Expected: FAIL — `Observer` not re-exported, `read` does not exist

- [ ] **Step 3: Re-export Observer in incr.mbt**

In `incr.mbt`, add `type Observer,` to the `pub using @internal` block:

```moonbit
pub using @internal {
  type Runtime,
  type CellInfo,
  type Signal,
  type Memo,
  type MemoMap,
  type CycleError,
  type TrackedCell,
  type HybridMemo,
  type Relation,
  type FunctionalRelation,
  type Reactive,
  type Effect,
  type Scope,
  type Observer,
}
```

- [ ] **Step 4: Add Runtime::read, read_hybrid, read_reactive in traits.mbt**

In `traits.mbt`, add after the `create_scope` function:

```moonbit
///|
/// One-shot observe: observe a memo, read its value, dispose the observer.
///
/// Convenience for cases where you need a single outside-the-graph read.
/// Equivalent to `memo.observe() |> .get()` followed by `obs.dispose()`.
///
/// # Panics
///
/// Aborts if the memo has been disposed.
pub fn[T] Runtime::read(self : Runtime, memo : Memo[T]) -> T {
  let obs = memo.observe()
  let val = obs.get()
  obs.dispose()
  val
}

///|
/// One-shot observe for HybridMemo.
pub fn[T : Eq] Runtime::read_hybrid(
  self : Runtime,
  memo : HybridMemo[T],
) -> T {
  let obs = memo.observe()
  let val = obs.get()
  obs.dispose()
  val
}

///|
/// One-shot observe for Reactive.
pub fn[T] Runtime::read_reactive(self : Runtime, reactive : Reactive[T]) -> T {
  let obs = reactive.observe()
  let val = obs.get()
  obs.dispose()
  val
}
```

- [ ] **Step 5: Run tests to verify they pass**

Run: `moon test -p dowdiness/incr/tests -f observer_test.mbt`
Expected: PASS (6 tests)

- [ ] **Step 6: Run full test suite for regressions**

Run: `moon test`
Expected: All tests pass

- [ ] **Step 7: Commit**

```bash
git add incr.mbt traits.mbt tests/observer_test.mbt
git commit -m "feat: re-export Observer, add Runtime::read convenience methods"
```

---

### Task 4: dispose_cell gc_root_counts cleanup

**Files:**
- Modify: `cells/runtime.mbt` (dispose_cell method)
- Test: `cells/gc_wbtest.mbt` (additional tests)

- [ ] **Step 1: Write tests for dispose_cell gc_root cleanup**

Append to `cells/gc_wbtest.mbt`:

```moonbit
///|
test "dispose_cell: removes gc_root_counts entry for observed cell" {
  let rt = Runtime::new()
  let sig = Signal::new(rt, 1)
  let m = Memo::new(rt, fn() { sig.get() })
  let obs = m.observe()
  // gc_root_counts has entry
  inspect(rt.core.gc_root_counts.get(m.id()).is_none(), content="false")
  // manually dispose the memo
  m.dispose()
  // gc_root_counts entry should be cleaned up
  inspect(rt.core.gc_root_counts.get(m.id()), content="None")
  // observer dispose should not abort (skips on_unobserve for dead cell)
  obs.dispose()
}

///|
test "dispose_cell: clears gc_root_counts with multiple observers" {
  let rt = Runtime::new()
  let sig = Signal::new(rt, 1)
  let m = Memo::new(rt, fn() { sig.get() })
  let obs1 = m.observe()
  let obs2 = m.observe()
  inspect(rt.core.gc_root_counts.get(m.id()), content="Some(2)")
  m.dispose()
  inspect(rt.core.gc_root_counts.get(m.id()), content="None")
  obs1.dispose()
  obs2.dispose()
}
```

- [ ] **Step 2: Run tests to verify they fail**

Run: `moon test -p dowdiness/incr/cells -f gc_wbtest.mbt`
Expected: FAIL — dispose_cell does not clear gc_root_counts

- [ ] **Step 3: Add gc_root_counts cleanup to dispose_cell**

In `cells/runtime.mbt`, modify `Runtime::dispose_cell` to remove gc_root_counts before dispatching:

```moonbit
pub fn Runtime::dispose_cell(self : Runtime, cell_id : CellId) -> Unit {
  guard cell_id.runtime_id == self.core.runtime_id else {
    abort("dispose_cell: CellId belongs to a different Runtime")
  }
  guard !self.is_cell_disposed(cell_id) else { return }
  self.guard_dispose(cell_id)
  // Clean up gc_root_counts to prevent leaks when observed cells
  // are manually disposed before their observers.
  self.core.gc_root_counts.remove(cell_id)
  self.core.cell_lifecycle[cell_id.id].dispose_cell(self, cell_id)
}
```

- [ ] **Step 4: Run tests to verify they pass**

Run: `moon test -p dowdiness/incr/cells -f gc_wbtest.mbt`
Expected: PASS (all gc_wbtest tests)

- [ ] **Step 5: Run full test suite for regressions**

Run: `moon test`
Expected: All tests pass

- [ ] **Step 6: Commit**

```bash
git add cells/runtime.mbt cells/gc_wbtest.mbt
git commit -m "fix: dispose_cell removes gc_root_counts entry to prevent observer leaks"
```

---

### Task 5: Runtime::gc() — mark-and-sweep

**Files:**
- Modify: `cells/runtime.mbt`
- Create: `cells/gc_test.mbt`

- [ ] **Step 1: Write gc() unit tests**

Create `cells/gc_test.mbt`:

```moonbit
///|
test "gc: disposes all unobserved interior cells" {
  let rt = Runtime::new()
  let sig = Signal::new(rt, 1)
  let m = Memo::new(rt, fn() { sig.get() * 2 })
  ignore(m.get())
  rt.gc()
  assert_true(m.is_disposed())
  // Source is never collected
  assert_false(sig.is_disposed())
}

///|
test "gc: keeps observed memo alive" {
  let rt = Runtime::new()
  let sig = Signal::new(rt, 1)
  let m = Memo::new(rt, fn() { sig.get() * 2 })
  let obs = m.observe()
  ignore(obs.get())
  rt.gc()
  assert_false(m.is_disposed())
  inspect(obs.get(), content="2")
  obs.dispose()
}

///|
test "gc: keeps transitive deps of observed memo alive" {
  let rt = Runtime::new()
  let sig = Signal::new(rt, 1)
  let m1 = Memo::new(rt, fn() { sig.get() + 1 })
  let m2 = Memo::new(rt, fn() { m1.get() * 2 })
  let obs = m2.observe()
  ignore(obs.get())
  rt.gc()
  assert_false(m1.is_disposed())
  assert_false(m2.is_disposed())
  obs.dispose()
}

///|
test "gc: disposes unreachable memo in diamond" {
  let rt = Runtime::new()
  let sig = Signal::new(rt, 1)
  let m_used = Memo::new(rt, fn() { sig.get() + 1 })
  let m_unused = Memo::new(rt, fn() { sig.get() + 2 })
  let m_top = Memo::new(rt, fn() { m_used.get() })
  let obs = m_top.observe()
  ignore(obs.get())
  ignore(m_unused.get()) // compute to establish deps, but not observed
  rt.gc()
  assert_false(m_used.is_disposed())
  assert_false(m_top.is_disposed())
  assert_true(m_unused.is_disposed()) // unreachable from any root
  obs.dispose()
}

///|
test "gc: after observer dispose sweeps newly-unreachable" {
  let rt = Runtime::new()
  let sig = Signal::new(rt, 1)
  let m = Memo::new(rt, fn() { sig.get() })
  let obs = m.observe()
  ignore(obs.get())
  obs.dispose()
  rt.gc()
  assert_true(m.is_disposed())
}

///|
test "gc: keeps effects alive as implicit roots" {
  let rt = Runtime::new()
  let sig = Signal::new(rt, 1)
  let m = Memo::new(rt, fn() { sig.get() })
  let log : Ref[Int] = { val: 0 }
  let _eff = Effect::new(rt, fn() {
    log.val = m.get()
  })
  rt.gc()
  // Effect is a root — m is reachable through Effect's sources
  assert_false(m.is_disposed())
}

///|
test "gc: skips sources (signals never collected)" {
  let rt = Runtime::new()
  let sig1 = Signal::new(rt, 1)
  let sig2 = Signal::new(rt, 2)
  rt.gc()
  assert_false(sig1.is_disposed())
  assert_false(sig2.is_disposed())
}

///|
test "gc: idempotent (running twice is safe)" {
  let rt = Runtime::new()
  let sig = Signal::new(rt, 1)
  let m = Memo::new(rt, fn() { sig.get() })
  ignore(m.get())
  rt.gc()
  assert_true(m.is_disposed())
  rt.gc() // second gc is a no-op
  assert_true(m.is_disposed())
}

///|
test "gc: after manual dispose is safe" {
  let rt = Runtime::new()
  let sig = Signal::new(rt, 1)
  let m = Memo::new(rt, fn() { sig.get() })
  ignore(m.get())
  m.dispose()
  rt.gc() // already disposed, gc skips it
  assert_true(m.is_disposed())
}

///|
test "gc: diamond keeps shared deps alive" {
  let rt = Runtime::new()
  let sig = Signal::new(rt, 1)
  let shared = Memo::new(rt, fn() { sig.get() })
  let left = Memo::new(rt, fn() { shared.get() + 1 })
  let right = Memo::new(rt, fn() { shared.get() + 2 })
  let obs_left = left.observe()
  ignore(obs_left.get())
  ignore(right.get()) // compute but not observed
  rt.gc()
  assert_false(shared.is_disposed()) // reachable from left
  assert_false(left.is_disposed())
  assert_true(right.is_disposed()) // unreachable
  obs_left.dispose()
}

///|
test "panic gc: during batch aborts" {
  let rt = Runtime::new()
  let sig = Signal::new(rt, 1)
  rt.batch(fn() {
    sig.set(2)
    rt.gc()
  })
}

///|
test "panic gc: during active computation aborts" {
  let rt = Runtime::new()
  let sig = Signal::new(rt, 1)
  let _m = Memo::new(rt, fn() {
    rt.gc()
    sig.get()
  })
  ignore(_m.get())
}

///|
test "panic gc: during push propagation aborts" {
  let rt = Runtime::new()
  let sig = Signal::new(rt, 1)
  let _eff = Effect::new(rt, fn() {
    ignore(sig.get())
    rt.gc()
  })
  sig.set(2) // triggers push propagation → effect runs → gc aborts
}
```

- [ ] **Step 2: Run tests to verify they fail**

Run: `moon test -p dowdiness/incr/cells -f gc_test.mbt`
Expected: FAIL — `Runtime::gc()` does not exist

- [ ] **Step 3: Implement gc(), gc_sweep, collect_gc_roots, mark_reachable**

In `cells/runtime.mbt`, add after `cell_id_at`:

```moonbit
///|
/// Runs mark-and-sweep garbage collection on the dependency graph.
///
/// Disposes all Interior cells (Memo, HybridMemo, Reactive) that are
/// unreachable from any gc root (observed cells) or implicit root (Effect).
/// Source cells (Signal, Relation, FunctionalRelation, Rule) are never collected.
///
/// gc() is opt-in — call it when you want to reclaim memory from
/// unobserved interior cells. Before Layer 5 boundary enforcement,
/// gc() may dispose cells that are still directly referenced via `.get()`.
///
/// # Panics
///
/// Aborts if called during active computation, batch, fixpoint, or push
/// propagation.
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

///|
/// Collects all GC roots: explicitly observed cells + implicit roots (Effects).
fn Runtime::collect_gc_roots(self : Runtime) -> Array[CellId] {
  let roots : Array[CellId] = []
  for id, _ in self.core.gc_root_counts {
    roots.push(id)
  }
  // Implicit roots: live cells with gc_role == Root (Effects)
  for i = 0; i < self.core.cell_ops.length(); i = i + 1 {
    match self.core.cell_index[i] {
      Disposed => continue
      _ => ()
    }
    if self.core.cell_ops[i].gc_role() is Root {
      roots.push(self.cell_id_at(i))
    }
  }
  roots
}

///|
/// Marks all cells reachable from `roots` via gc_dependencies BFS.
fn Runtime::mark_reachable(
  self : Runtime,
  roots : Array[CellId],
) -> @hashset.HashSet[CellId] {
  let reachable : @hashset.HashSet[CellId] = @hashset.new()
  let worklist : Array[CellId] = Array::from(roots)
  let mut wi = 0
  while wi < worklist.length() {
    let id = worklist[wi]
    wi += 1
    if reachable.contains(id) {
      continue
    }
    match self.core.cell_index[id.id] {
      Disposed => continue
      _ => ()
    }
    reachable.add(id)
    for dep in self.core.cell_ops[id.id].gc_dependencies() {
      worklist.push(dep)
    }
  }
  reachable
}

///|
/// Sweep phase: dispose Interior cells not in the reachable set.
fn Runtime::gc_sweep(self : Runtime) -> Unit {
  let roots = self.collect_gc_roots()
  let reachable = self.mark_reachable(roots)
  for i = 0; i < self.core.cell_ops.length(); i = i + 1 {
    match self.core.cell_index[i] {
      Disposed => continue
      _ => ()
    }
    if self.core.cell_ops[i].gc_role() is Interior {
      let id = self.cell_id_at(i)
      if !reachable.contains(id) {
        self.dispose_cell(id)
      }
    }
  }
}
```

- [ ] **Step 4: Run tests to verify they pass**

Run: `moon test -p dowdiness/incr/cells -f gc_test.mbt`
Expected: PASS (13 tests)

- [ ] **Step 5: Run full test suite for regressions**

Run: `moon test`
Expected: All tests pass

- [ ] **Step 6: Commit**

```bash
git add cells/runtime.mbt cells/gc_test.mbt
git commit -m "feat: add Runtime::gc() mark-and-sweep for unreachable interior cells"
```

---

### Task 6: gc() integration tests

**Files:**
- Create: `tests/gc_test.mbt`

- [ ] **Step 1: Write integration tests**

Create `tests/gc_test.mbt`:

```moonbit
///|
test "gc: observe → signal.set → observer.get sees update" {
  let rt = @incr.Runtime()
  let sig = @incr.Signal(rt, 10)
  let m = @incr.Memo(rt, fn() { sig.get() * 2 })
  let obs = m.observe()
  inspect(obs.get(), content="20")
  sig.set(15)
  inspect(obs.get(), content="30")
  obs.dispose()
}

///|
test "gc: scope dispose + gc sweeps orphaned interior cells" {
  let rt = @incr.Runtime()
  let sig = @incr.Signal(rt, 1)
  let scope = @incr.Scope(rt)
  let m = scope.memo(fn() { sig.get() + 1 })
  let obs = m.observe()
  ignore(obs.get())

  // Create another memo not observed
  let m_orphan = @incr.Memo(rt, fn() { sig.get() + 2 })
  ignore(m_orphan.get())

  obs.dispose()
  scope.dispose()
  rt.gc()
  assert_true(m.is_disposed()) // disposed by scope
  assert_true(m_orphan.is_disposed()) // swept by gc
}

///|
test "gc: Runtime::read does not leak gc roots" {
  let rt = @incr.Runtime()
  let sig = @incr.Signal(rt, 5)
  let m = @incr.Memo(rt, fn() { sig.get() * 3 })
  let val = rt.read(m)
  inspect(val, content="15")
  // After read, no gc roots should remain for m
  rt.gc()
  assert_true(m.is_disposed())
}

///|
test "gc: manual dispose of observed cell then gc" {
  let rt = @incr.Runtime()
  let sig = @incr.Signal(rt, 1)
  let m = @incr.Memo(rt, fn() { sig.get() })
  let obs = m.observe()
  ignore(obs.get())
  m.dispose()
  obs.dispose() // safe — skips on_unobserve for dead cell
  rt.gc() // safe — m already disposed
}

///|
test "gc: hybrid memo reachable through observer" {
  let rt = @incr.Runtime()
  let sig = @incr.Signal(rt, 1)
  let h = @incr.HybridMemo(rt, fn() { sig.get() + 10 })
  let obs = h.observe()
  inspect(obs.get(), content="11")
  rt.gc()
  assert_false(h.is_disposed())
  obs.dispose()
  rt.gc()
  assert_true(h.is_disposed())
}

///|
test "gc: reactive reachable through observer" {
  let rt = @incr.Runtime()
  let sig = @incr.Signal(rt, 1)
  let r = @incr.Reactive(rt, fn() { sig.get() * 4 })
  let obs = r.observe()
  inspect(obs.get(), content="4")
  rt.gc()
  assert_false(r.is_disposed())
  obs.dispose()
  rt.gc()
  assert_true(r.is_disposed())
}
```

- [ ] **Step 2: Run tests to verify they pass**

Run: `moon test -p dowdiness/incr/tests -f gc_test.mbt`
Expected: PASS (6 tests)

- [ ] **Step 3: Run full test suite**

Run: `moon test`
Expected: All tests pass

- [ ] **Step 4: Commit**

```bash
git add tests/gc_test.mbt
git commit -m "test: add gc() and observer integration tests"
```

---

### Task 7: Benchmarks + moon info + moon fmt

**Files:**
- Modify: `tests/bench_test.mbt`

- [ ] **Step 1: Add Layer 4a benchmarks**

Append to `tests/bench_test.mbt`:

```moonbit
///|
// ─── Layer 4a: Observer + gc() ──────────────────────────────────────────────

///|
test "observer: get warm (memo)" (b : @bench.T) {
  let rt = @incr.Runtime()
  let sig = @incr.Signal(rt, 42)
  let m = @incr.Memo(rt, fn() { sig.get() * 2 })
  let obs = m.observe()
  ignore(obs.get()) // prime
  b.bench(fn() { b.keep(obs.get()) })
  obs.dispose()
}

///|
test "observer: observe + dispose cycle" (b : @bench.T) {
  let rt = @incr.Runtime()
  let sig = @incr.Signal(rt, 42)
  let m = @incr.Memo(rt, fn() { sig.get() * 2 })
  ignore(m.get()) // prime
  b.bench(fn() {
    let obs = m.observe()
    b.keep(obs.get())
    obs.dispose()
  })
}

///|
test "gc: sweep 1k all-live" (b : @bench.T) {
  let rt = @incr.Runtime()
  let sig = @incr.Signal(rt, 1)
  let observers : Array[@incr.Observer[Int]] = []
  for i = 0; i < 1000; i = i + 1 {
    let m = @incr.Memo(rt, fn() { sig.get() + i })
    let obs = m.observe()
    ignore(obs.get())
    observers.push(obs)
  }
  b.bench(fn() { rt.gc() })
  for obs in observers {
    obs.dispose()
  }
}

///|
test "gc: sweep 1k all-dead" (b : @bench.T) {
  let rt = @incr.Runtime()
  let sig = @incr.Signal(rt, 1)
  for i = 0; i < 1000; i = i + 1 {
    let m = @incr.Memo(rt, fn() { sig.get() + i })
    ignore(m.get())
  }
  // First gc disposes all, subsequent gcs are sweeps over Disposed entries
  rt.gc()
  b.bench(fn() { rt.gc() })
}

///|
test "gc: sweep 1k 50pct dead" (b : @bench.T) {
  let rt = @incr.Runtime()
  let sig = @incr.Signal(rt, 1)
  let observers : Array[@incr.Observer[Int]] = []
  for i = 0; i < 1000; i = i + 1 {
    let m = @incr.Memo(rt, fn() { sig.get() + i })
    let obs = m.observe()
    ignore(obs.get())
    if i % 2 == 0 {
      obs.dispose()
    } else {
      observers.push(obs)
    }
  }
  b.bench(fn() { rt.gc() })
  for obs in observers {
    obs.dispose()
  }
}

///|
test "runtime: read one-shot" (b : @bench.T) {
  let rt = @incr.Runtime()
  let sig = @incr.Signal(rt, 42)
  let m = @incr.Memo(rt, fn() { sig.get() * 2 })
  ignore(m.get()) // prime
  b.bench(fn() { b.keep(rt.read(m)) })
}
```

- [ ] **Step 2: Run benchmarks**

Run: `moon bench --release`
Expected: Benchmarks run without errors

- [ ] **Step 3: Run moon info and moon fmt**

Run: `moon info && moon fmt`

- [ ] **Step 4: Check .mbti changes**

Run: `git diff *.mbti`
Expected: New entries for `Observer[T]`, `Memo::observe`, `HybridMemo::observe`, `Reactive::observe`, `Observer::get`, `Observer::dispose`, `Observer::is_disposed`, `Runtime::gc`, `Runtime::read`, `Runtime::read_hybrid`, `Runtime::read_reactive`

- [ ] **Step 5: Run full test suite one final time**

Run: `moon test`
Expected: All tests pass

- [ ] **Step 6: Commit**

```bash
git add tests/bench_test.mbt
git add -u  # catch moon info/fmt changes
git commit -m "feat: add Layer 4a benchmarks, regenerate .mbti interfaces"
```
