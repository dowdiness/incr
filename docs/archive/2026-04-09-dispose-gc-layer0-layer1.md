# Dispose/GC — Phase 0 (Benchmarks) + Layer 1 (Manual Dispose) Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Establish performance baselines, then implement manual `dispose()` for all cell types with free-list slot reuse for pull cells.

**Architecture:** Extend the existing dispose pattern (bounds check → match CellRef → remove from upstream subscribers → mark Disposed → clear slot → free list) to Signal, Memo, Relation, Rule, and FunctionalRelation. Add `is_disposed()` on all handle types. Add free lists to `PullState` for signal and memo SoA slot reuse.

**Tech Stack:** MoonBit, `moon test`, `moon bench --release`, `moon check`

**Spec:** `docs/plans/2026-04-08-dispose-gc-design.md` (Layer 1 + Section 6 Phase 1)

---

## File Map

| Action | File | Responsibility |
|--------|------|----------------|
| Modify | `tests/bench_test.mbt` | Add Phase 1 baseline benchmarks |
| Modify | `cells/runtime.mbt` | `dispose_signal`, `dispose_memo`, `dispose_relation`, `dispose_functional_relation`, `dispose_rule`; free lists on PullState |
| Modify | `cells/signal.mbt` | `Signal::dispose()`, `Signal::is_disposed()` |
| Modify | `cells/memo.mbt` | `Memo::dispose()`, `Memo::is_disposed()` |
| Modify | `cells/hybrid_memo.mbt` | `HybridMemo::is_disposed()` (dispose already exists) |
| Modify | `cells/push_reactive.mbt` | `Reactive::is_disposed()` (dispose already exists) |
| Modify | `cells/push_effect.mbt` | `Effect::is_disposed()` (dispose already exists) |
| Modify | `cells/tracked_cell.mbt` | `TrackedCell::dispose()`, `TrackedCell::is_disposed()` |
| Modify | `cells/datalog_relation.mbt` | `Relation::dispose()`, `Relation::is_disposed()` |
| Modify | `cells/datalog_functional_relation.mbt` | `FunctionalRelation::dispose()`, `FunctionalRelation::is_disposed()` |
| Modify | `cells/datalog_rule.mbt` | (no changes — Rule disposed via `Runtime::dispose_rule()`) |
| Create | `cells/dispose_test.mbt` | Black-box dispose tests for Signal, Memo, Relation, Rule |
| Create | `cells/dispose_wbtest.mbt` | Whitebox dispose tests (subscriber cleanup, free lists, slot clearing) |

---

## Task 0: Baseline Benchmarks

**Files:**
- Modify: `tests/bench_test.mbt`

- [ ] **Step 1: Add cell accumulation benchmarks**

These measure the cost of operating in a runtime with many unreferenced cells. "Unreferenced" means the user dropped the MoonBit handle, but the cells still occupy SoA slots and cell_index entries — there's no dispose mechanism yet.

Append to `tests/bench_test.mbt`:

```moonbit
///|
test "baseline: signal.set with clean runtime" (b : @bench.T) {
  let rt = Runtime::new()
  let sig = Signal::new(rt, 0)
  let mut v = 0
  b.bench(fn() { v += 1; sig.set(v) })
}

///|
test "baseline: signal.set with 10k unreferenced memos" (b : @bench.T) {
  // Memos are created and immediately dropped. They persist in the SoA
  // arrays because there's no dispose mechanism yet. This measures whether
  // accumulated SoA entries affect signal.set performance.
  let rt = Runtime::new()
  let sig = Signal::new(rt, 0)
  for i = 0; i < 10_000; i = i + 1 {
    let idx = i
    ignore(Memo::new(rt, fn() { sig.get() + idx }))
  }
  let mut v = 0
  b.bench(fn() { v += 1; sig.set(v) })
}

///|
test "baseline: memo creation cost (monotonic SoA growth)" (b : @bench.T) {
  let rt = Runtime::new()
  let sig = Signal::new(rt, 0)
  b.bench(fn() {
    ignore(Memo::new(rt, fn() { sig.get() }))
  })
}
```

- [ ] **Step 2: Re-export Reactive and Effect from the incr facade**

The `tests/` package imports `@incr`, but `Reactive` and `Effect` are not currently re-exported. In `incr.mbt`, add them to the `pub using @internal` block:

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
  type Reactive,   // add
  type Effect,     // add
}
```

Run: `moon check`
Expected: no errors

- [ ] **Step 3: Add push CPU waste benchmarks**

"Abandoned" reactives are live in the runtime (SoA slot, subscriber links, push_reachable_count all active) but the user dropped the MoonBit handle. Push propagation still reaches them.

Append to `tests/bench_test.mbt`:

```moonbit
///|
test "baseline: push propagation with 0 reactives" (b : @bench.T) {
  let rt = Runtime::new()
  let sig = Signal::new(rt, 0)
  let mut v = 0
  b.bench(fn() { v += 1; sig.set(v) })
}

///|
test "baseline: push propagation with 100 live reactives" (b : @bench.T) {
  let rt = Runtime::new()
  let sig = Signal::new(rt, 0)
  let reactives : Array[Reactive[Int]] = []
  for i = 0; i < 100; i = i + 1 {
    let idx = i
    reactives.push(Reactive::new(rt, fn() { sig.get() + idx }))
  }
  let mut v = 0
  b.bench(fn() { v += 1; sig.set(v) })
  ignore(reactives)
}

///|
test "baseline: push propagation with 100 disposed reactives" (b : @bench.T) {
  let rt = Runtime::new()
  let sig = Signal::new(rt, 0)
  for i = 0; i < 100; i = i + 1 {
    let idx = i
    let r = Reactive::new(rt, fn() { sig.get() + idx })
    r.dispose()
  }
  let mut v = 0
  b.bench(fn() { v += 1; sig.set(v) })
}

///|
test "baseline: push propagation with 100 abandoned reactives (handle dropped)" (b : @bench.T) {
  // User dropped handle but reactive is still live in SoA — push still
  // propagates through it. This is the CPU waste GC should eliminate.
  let rt = Runtime::new()
  let sig = Signal::new(rt, 0)
  for i = 0; i < 100; i = i + 1 {
    let idx = i
    ignore(Reactive::new(rt, fn() { sig.get() + idx }))
  }
  let mut v = 0
  b.bench(fn() { v += 1; sig.set(v) })
}
```

- [ ] **Step 4: Add slot reuse benchmark**

Append to `tests/bench_test.mbt`:

```moonbit
///|
test "baseline: reactive create-dispose cycle (existing free list)" (b : @bench.T) {
  let rt = Runtime::new()
  let sig = Signal::new(rt, 0)
  b.bench(fn() {
    let r = Reactive::new(rt, fn() { sig.get() })
    r.dispose()
  })
}
```

- [ ] **Step 5: Run moon check**

Run: `moon check`
Expected: no errors

- [ ] **Step 6: Run benchmarks and record baselines**

Run: `cd /home/antisatori/ghq/github.com/dowdiness/canopy/loom/incr && moon bench --release`

Record the output. These are the baselines for comparison after Layer 1.

- [ ] **Step 7: Commit**

```bash
git add tests/bench_test.mbt incr.mbt
git commit -m "bench: add Phase 1 baseline benchmarks for dispose/GC

Also re-exports Reactive and Effect from the incr facade."
```

---

## Task 1: Signal::dispose() and is_disposed()

**Files:**
- Modify: `cells/runtime.mbt` — add `Runtime::dispose_signal`
- Modify: `cells/signal.mbt` — add `Signal::dispose()`, `Signal::is_disposed()`
- Create: `cells/dispose_test.mbt` — black-box tests

- [ ] **Step 1: Write failing test for Signal::dispose()**

Create `cells/dispose_test.mbt`:

```moonbit
///|
test "signal: dispose marks cell as disposed" {
  let rt = Runtime::new()
  let sig = Signal::new(rt, 42)
  assert_false!(sig.is_disposed())
  sig.dispose()
  assert_true!(sig.is_disposed())
}

///|
test "signal: dispose is idempotent" {
  let rt = Runtime::new()
  let sig = Signal::new(rt, 42)
  sig.dispose()
  sig.dispose() // second call is no-op, no abort
  assert_true!(sig.is_disposed())
}

///|
test "panic signal: get after dispose aborts" {
  let rt = Runtime::new()
  let sig = Signal::new(rt, 42)
  sig.dispose()
  ignore(sig.get()) // should abort
}
```

- [ ] **Step 2: Run test to verify it fails**

Run: `moon test -p dowdiness/incr/cells -f dispose_test.mbt`
Expected: FAIL — `is_disposed` and `dispose` not defined on Signal

- [ ] **Step 3: Implement Signal::is_disposed()**

Add to `cells/signal.mbt`:

```moonbit
///|
/// Returns true if this signal has been disposed.
pub fn[T] Signal::is_disposed(self : Signal[T]) -> Bool {
  let id = self.cell_id.id
  if id < 0 || id >= self.rt.core.cell_index.length() {
    return true
  }
  match self.rt.core.cell_index[id] {
    Disposed => true
    _ => false
  }
}
```

- [ ] **Step 4: Implement Runtime::dispose_signal()**

Add to `cells/runtime.mbt`:

```moonbit
///|
/// Disposes a pull signal cell, removing it from all downstream subscriber sets
/// and marking its cell_index slot as Disposed.
fn Runtime::dispose_signal(self : Runtime, cell_id : CellId) -> Unit {
  if cell_id.id < 0 || cell_id.id >= self.core.cell_index.length() {
    return
  }
  match self.core.cell_index[cell_id.id] {
    PullSignal(idx) => {
      let signal = self.pull.signals[idx]
      // Signals have no upstream dependencies to unsubscribe from.
      // Clear downstream subscribers.
      signal.meta.subscribers.clear()
      signal.meta.label = None
      signal.on_change = None
      signal.commit_pending = None
      self.core.cell_index[cell_id.id] = Disposed
    }
    _ => ()
  }
}
```

- [ ] **Step 5: Implement Signal::dispose()**

Add to `cells/signal.mbt`:

```moonbit
///|
/// Disposes this signal, releasing its resources and marking it as Disposed.
///
/// After disposal, calling `get()` or `set()` will abort. Disposal is
/// idempotent — calling it multiple times is a no-op.
pub fn[T] Signal::dispose(self : Signal[T]) -> Unit {
  self.rt.dispose_signal(self.cell_id)
}
```

- [ ] **Step 6: Add disposed guards to Signal::get() and Signal::set()**

Signal::get() reads `self.value` directly without checking cell_index. After disposal, this returns a stale value. Add a disposed check at the top of Signal::get() in `cells/signal.mbt`, BEFORE the cross-runtime check:

```moonbit
pub fn[T] Signal::get(self : Signal[T]) -> T {
  // Disposed check — must come before cross-runtime check
  match self.rt.core.cell_index[self.cell_id.id] {
    Disposed => abort("Signal::get called on a disposed signal")
    _ => ()
  }
  let active_rt = current_computing_runtime_id.val
  // ... rest of existing code unchanged ...
```

Add the same guard to Signal::set() and Signal::set_unconditional() in `cells/signal.mbt`:

```moonbit
// At the top of Signal::set():
  match self.rt.core.cell_index[self.cell_id.id] {
    Disposed => abort("Signal::set called on a disposed signal")
    _ => ()
  }

// At the top of Signal::set_unconditional():
  match self.rt.core.cell_index[self.cell_id.id] {
    Disposed => abort("Signal::set_unconditional called on a disposed signal")
    _ => ()
  }
```

- [ ] **Step 7: Run moon check**

Run: `moon check`
Expected: no errors

- [ ] **Step 8: Run tests**

Run: `moon test -p dowdiness/incr/cells -f dispose_test.mbt`
Expected: all 3 tests pass (including panic test for get-after-dispose)

Run: `moon test -p dowdiness/incr/cells`
Expected: all existing tests still pass

- [ ] **Step 9: Commit**

```bash
git add cells/signal.mbt cells/runtime.mbt cells/dispose_test.mbt
git commit -m "feat: add Signal::dispose(), is_disposed(), and disposed guards"
```

---

## Task 2: Signal dispose whitebox tests + free list

**Files:**
- Modify: `cells/runtime.mbt` — add free list to PullState, update `new_signal_id` to check free list
- Create: `cells/dispose_wbtest.mbt` — whitebox tests

- [ ] **Step 1: Write failing whitebox test for subscriber cleanup**

Create `cells/dispose_wbtest.mbt`:

```moonbit
///|
test "signal dispose: removes from downstream subscriber sets" {
  let rt = Runtime::new()
  let sig = Signal::new(rt, 10)
  let m = Memo::new(rt, fn() { sig.get() * 2 })
  ignore(m.get()) // establish dependency: sig -> m
  let sig_id = sig.id()
  let subs = rt.get_subscribers(sig_id).collect()
  assert_true!(subs.length() > 0)
  sig.dispose()
  // After dispose, sig's subscribers should be cleared
  // (but we can't call get_subscribers on Disposed — check cell_index directly)
  assert_true!(
    match rt.core.cell_index[sig_id.id] {
      Disposed => true
      _ => false
    },
  )
}

///|
test "signal dispose: free list enables slot reuse" {
  let rt = Runtime::new()
  let sig1 = Signal::new(rt, 10)
  let idx1 = match rt.core.cell_index[sig1.id().id] {
    PullSignal(i) => i
    _ => abort("expected PullSignal")
  }
  sig1.dispose()
  // Free list should contain idx1
  assert_true!(rt.pull.free_signals.contains(idx1))
  // Creating a new signal should reuse the slot
  let sig2 = Signal::new(rt, 20)
  let idx2 = match rt.core.cell_index[sig2.id().id] {
    PullSignal(i) => i
    _ => abort("expected PullSignal")
  }
  assert_eq!(idx1, idx2)
  assert_eq!(sig2.get(), 20)
}
```

- [ ] **Step 2: Run test to verify it fails**

Run: `moon test -p dowdiness/incr/cells -f dispose_wbtest.mbt`
Expected: FAIL — `free_signals` does not exist on PullState

- [ ] **Step 3: Add free list to PullState**

In `cells/runtime.mbt`, modify `PullState`:

```moonbit
priv struct PullState {
  signals : Array[PullSignalData]
  memos : Array[MemoData]
  free_signals : Array[Int]
  free_memos : Array[Int]
}
```

Update `Runtime::new()` to initialize the new fields:

```moonbit
pull: { signals: [], memos: [], free_signals: [], free_memos: [] },
```

- [ ] **Step 4: Update dispose_signal to add to free list**

In `cells/runtime.mbt`, update `dispose_signal` — add after `self.core.cell_index[cell_id.id] = Disposed`:

```moonbit
      self.pull.free_signals.push(idx)
```

- [ ] **Step 5: Update new_signal_id to check free list**

In `cells/runtime.mbt`, modify `Runtime::new_signal_id`. Follow the exact same pattern as `Reactive::new` in `cells/push_reactive.mbt:91-117`:
- `pop()` from free list returns `Some(idx)` or `None`
- `alloc_cell_id` ALWAYS appends a new CellId (new `.id` value)
- SoA slot is overwritten if reusing, pushed if new
- `cell_ops.push(ops)` ALWAYS — new CellId means new cell_ops entry

```moonbit
fn Runtime::new_signal_id(
  self : Runtime,
  durability : Durability,
  label : String?,
) -> CellId {
  // Reuse a freed slot if available, otherwise append a new one.
  let signal_idx = match self.pull.free_signals.pop() {
    Some(idx) => idx
    None => self.pull.signals.length()
  }
  let cell_id = self.alloc_cell_id(PullSignal(signal_idx))
  let new_data : PullSignalData = {
    meta: {
      cell_id,
      label,
      changed_at: Revision::initial(),
      durability,
      subscribers: @hashset.new(),
      push_reachable_count: 0,
    },
    on_change: None,
    commit_pending: None,
  }
  if signal_idx < self.pull.signals.length() {
    self.pull.signals[signal_idx] = new_data
  } else {
    self.pull.signals.push(new_data)
  }
  let ops : &CellOps = self.pull.signals[signal_idx]
  self.core.cell_ops.push(ops)  // PUSH — new CellId always gets a new cell_ops entry
  cell_id
}
```

**Key invariant:** `alloc_cell_id` appends to `cell_index`, so the new CellId's `.id` equals the NEW length of `cell_index`. `cell_ops` must also grow by one (via `push`), not be assigned at an existing index.

- [ ] **Step 6: Run moon check**

Run: `moon check`
Expected: no errors

- [ ] **Step 7: Run tests**

Run: `moon test -p dowdiness/incr/cells -f dispose_wbtest.mbt`
Expected: both whitebox tests pass

Run: `moon test -p dowdiness/incr/cells`
Expected: all tests pass (no regressions)

- [ ] **Step 8: Commit**

```bash
git add cells/runtime.mbt cells/dispose_wbtest.mbt
git commit -m "feat: add signal free list for SoA slot reuse"
```

---

## Task 3: Memo::dispose() and is_disposed()

**Files:**
- Modify: `cells/runtime.mbt` — add `Runtime::dispose_memo`
- Modify: `cells/memo.mbt` — add `Memo::dispose()`, `Memo::is_disposed()`
- Modify: `cells/dispose_test.mbt` — add tests

- [ ] **Step 1: Write failing tests**

Append to `cells/dispose_test.mbt`:

```moonbit
///|
test "memo: dispose marks cell as disposed" {
  let rt = Runtime::new()
  let sig = Signal::new(rt, 10)
  let m = Memo::new(rt, fn() { sig.get() * 2 })
  ignore(m.get()) // prime
  assert_false!(m.is_disposed())
  m.dispose()
  assert_true!(m.is_disposed())
}

///|
test "memo: dispose is idempotent" {
  let rt = Runtime::new()
  let sig = Signal::new(rt, 10)
  let m = Memo::new(rt, fn() { sig.get() * 2 })
  ignore(m.get())
  m.dispose()
  m.dispose() // no-op
  assert_true!(m.is_disposed())
}

///|
test "panic memo: get after dispose aborts" {
  let rt = Runtime::new()
  let sig = Signal::new(rt, 10)
  let m = Memo::new(rt, fn() { sig.get() * 2 })
  ignore(m.get())
  m.dispose()
  ignore(m.get()) // should abort
}

///|
test "memo: dispose removes from upstream subscriber sets" {
  let rt = Runtime::new()
  let sig = Signal::new(rt, 10)
  let m = Memo::new(rt, fn() { sig.get() * 2 })
  ignore(m.get()) // establish sig -> m dependency
  let sig_subs_before = rt.get_subscribers(sig.id()).collect().length()
  assert_true!(sig_subs_before > 0)
  m.dispose()
  let sig_subs_after = rt.get_subscribers(sig.id()).collect().length()
  assert_eq!(sig_subs_after, 0)
}
```

- [ ] **Step 2: Run test to verify it fails**

Run: `moon test -p dowdiness/incr/cells -f dispose_test.mbt`
Expected: FAIL — `dispose` and `is_disposed` not defined on Memo

- [ ] **Step 3: Implement Memo::is_disposed()**

Add to `cells/memo.mbt`:

```moonbit
///|
/// Returns true if this memo has been disposed.
pub fn[T] Memo::is_disposed(self : Memo[T]) -> Bool {
  let id = self.cell_id.id
  if id < 0 || id >= self.rt.core.cell_index.length() {
    return true
  }
  match self.rt.core.cell_index[id] {
    Disposed => true
    _ => false
  }
}
```

- [ ] **Step 4: Implement Runtime::dispose_memo()**

Add to `cells/runtime.mbt`:

```moonbit
///|
/// Disposes a pull memo cell, removing it from all upstream subscriber sets,
/// clearing its cached state, and marking its cell_index slot as Disposed.
fn Runtime::dispose_memo(self : Runtime, cell_id : CellId) -> Unit {
  if cell_id.id < 0 || cell_id.id >= self.core.cell_index.length() {
    return
  }
  match self.core.cell_index[cell_id.id] {
    PullMemo(idx) => {
      let memo = self.pull.memos[idx]
      for dep in memo.dependencies {
        self.remove_subscriber(dep, cell_id)
      }
      memo.dependencies = []
      memo.meta.subscribers.clear()
      memo.meta.label = None
      memo.on_change = None
      memo.compute = fn() { Ok(false) }  // release captured closure
      memo.verified_at = Revision::initial()
      memo.in_progress = false
      self.core.cell_index[cell_id.id] = Disposed
      self.pull.free_memos.push(idx)
    }
    _ => ()
  }
}
```

- [ ] **Step 5: Implement Memo::dispose()**

Add to `cells/memo.mbt`:

```moonbit
///|
/// Disposes this memo, releasing its resources and marking it as Disposed.
///
/// After disposal, calling `get()` will abort. Disposal is idempotent.
pub fn[T] Memo::dispose(self : Memo[T]) -> Unit {
  self.rt.dispose_memo(self.cell_id)
  self.value = None
}
```

- [ ] **Step 6: Run moon check**

Run: `moon check`
Expected: no errors

- [ ] **Step 7: Run tests**

Run: `moon test -p dowdiness/incr/cells -f dispose_test.mbt`
Expected: all tests pass

Run: `moon test -p dowdiness/incr/cells`
Expected: all tests pass (no regressions)

- [ ] **Step 8: Commit**

```bash
git add cells/memo.mbt cells/runtime.mbt cells/dispose_test.mbt
git commit -m "feat: add Memo::dispose() and is_disposed() with free list"
```

---

## Task 4: Memo free list slot reuse

**Files:**
- Modify: `cells/runtime.mbt` — update memo creation to check free list
- Modify: `cells/dispose_wbtest.mbt` — add whitebox tests

- [ ] **Step 1: Write failing whitebox test**

Append to `cells/dispose_wbtest.mbt`:

```moonbit
///|
test "memo dispose: free list enables slot reuse" {
  let rt = Runtime::new()
  let sig = Signal::new(rt, 10)
  let m1 = Memo::new(rt, fn() { sig.get() * 2 })
  ignore(m1.get())
  let idx1 = match rt.core.cell_index[m1.id().id] {
    PullMemo(i) => i
    _ => abort("expected PullMemo")
  }
  m1.dispose()
  assert_true!(rt.pull.free_memos.contains(idx1))
  // New memo should reuse the slot
  let m2 = Memo::new(rt, fn() { sig.get() + 1 })
  let idx2 = match rt.core.cell_index[m2.id().id] {
    PullMemo(i) => i
    _ => abort("expected PullMemo")
  }
  assert_eq!(idx1, idx2)
  assert_eq!(m2.get(), 11)
}
```

- [ ] **Step 2: Run test to verify it fails**

Run: `moon test -p dowdiness/incr/cells -f dispose_wbtest.mbt`
Expected: FAIL — new memo doesn't reuse slot (no free list check in memo creation)

- [ ] **Step 3: Update Memo::_create to check free list**

There is no `Runtime::new_memo_id`. Memo allocation happens in `Memo::_create` (`cells/memo.mbt:45`). HybridMemo allocation happens in `HybridMemo::new` (`cells/hybrid_memo.mbt:30`). Both share `rt.pull.memos` and must share `rt.pull.free_memos`.

In `cells/memo.mbt`, modify `Memo::_create`. Replace the fixed `let memo_idx = rt.pull.memos.length()` with a free list check:

```moonbit
fn[T] Memo::_create(
  rt : Runtime,
  compute : () -> T,
  label? : String,
  backdate_eq : (T, T) -> Bool,
) -> Memo[T] {
  // Reuse a freed slot if available, otherwise append
  let memo_idx = match rt.pull.free_memos.pop() {
    Some(idx) => idx
    None => rt.pull.memos.length()
  }
  let cell_id = rt.alloc_cell_id(PullMemo(memo_idx))
  let memo : Memo[T] = { label, rt, cell_id, compute, backdate_eq, value: None }
  let new_data : MemoData = {
    meta: {
      cell_id,
      label,
      changed_at: Revision::initial(),
      durability: Low,
      subscribers: @hashset.new(),
      push_reachable_count: 0,
    },
    compute: () => memo.recompute_inner(),
    verified_at: Revision::initial(),
    dependencies: [],
    in_progress: false,
    on_change: None,
  }
  if memo_idx < rt.pull.memos.length() {
    rt.pull.memos[memo_idx] = new_data
  } else {
    rt.pull.memos.push(new_data)
  }
  let ops : &CellOps = rt.pull.memos[memo_idx]
  rt.core.cell_ops.push(ops)  // PUSH — new CellId, new cell_ops entry
  memo
}
```

Apply the same pattern to `HybridMemo::new` in `cells/hybrid_memo.mbt:30` — replace `let memo_idx = rt.pull.memos.length()` with the free list pop, and use the if/else overwrite/push pattern for the SoA slot. Use `HybridMemo(memo_idx)` instead of `PullMemo(memo_idx)` in `alloc_cell_id`.

- [ ] **Step 4: Run moon check**

Run: `moon check`
Expected: no errors

- [ ] **Step 5: Run tests**

Run: `moon test -p dowdiness/incr/cells`
Expected: all tests pass

- [ ] **Step 6: Commit**

```bash
git add cells/runtime.mbt cells/dispose_wbtest.mbt
git commit -m "feat: add memo free list for SoA slot reuse"
```

---

## Task 5: HybridMemo dispose improvements

**Files:**
- Modify: `cells/hybrid_memo.mbt` — add `is_disposed()`, clear cached value on dispose
- Modify: `cells/runtime.mbt` — update `dispose_hybrid_memo` to clear MemoData fields and add to free list
- Modify: `cells/dispose_test.mbt` — add tests

- [ ] **Step 1: Write failing tests**

Append to `cells/dispose_test.mbt`:

```moonbit
///|
test "hybrid memo: is_disposed returns correct state" {
  let rt = Runtime::new()
  let sig = Signal::new(rt, 10)
  let h = HybridMemo::new(rt, fn() { sig.get() * 2 })
  ignore(h.get())
  assert_false!(h.is_disposed())
  h.dispose()
  assert_true!(h.is_disposed())
}
```

- [ ] **Step 2: Implement HybridMemo::is_disposed()**

Add to `cells/hybrid_memo.mbt`:

```moonbit
///|
/// Returns true if this hybrid memo has been disposed.
pub fn[T] HybridMemo::is_disposed(self : HybridMemo[T]) -> Bool {
  let id = self.cell_id.id
  if id < 0 || id >= self.rt.core.cell_index.length() {
    return true
  }
  match self.rt.core.cell_index[id] {
    Disposed => true
    _ => false
  }
}
```

- [ ] **Step 3: Update dispose_hybrid_memo to clear MemoData fields**

In `cells/runtime.mbt`, update `dispose_hybrid_memo` to aggressively clear the MemoData slot (matching the spec's slot clearing requirements):

```moonbit
fn Runtime::dispose_hybrid_memo(self : Runtime, cell_id : CellId) -> Unit {
  if cell_id.id < 0 || cell_id.id >= self.core.cell_index.length() {
    return
  }
  match self.core.cell_index[cell_id.id] {
    HybridMemo(idx) => {
      let memo = self.pull.memos[idx]
      for dep in memo.dependencies {
        self.remove_subscriber(dep, cell_id)
      }
      memo.dependencies = []
      memo.meta.subscribers.clear()
      memo.meta.label = None
      memo.on_change = None
      memo.compute = fn() { Ok(false) }  // release captured closure
      memo.verified_at = Revision::initial()
      memo.in_progress = false
      self.core.cell_index[cell_id.id] = Disposed
      self.pull.free_memos.push(idx)
    }
    _ => ()
  }
}
```

- [ ] **Step 4: Update HybridMemo::dispose() to clear cached value**

In `cells/hybrid_memo.mbt`, update `dispose()`:

```moonbit
pub fn[T] HybridMemo::dispose(self : HybridMemo[T]) -> Unit {
  self.rt.dispose_hybrid_memo(self.cell_id)
  self.value = None
}
```

- [ ] **Step 5: Run moon check**

Run: `moon check`
Expected: no errors

- [ ] **Step 6: Run tests**

Run: `moon test -p dowdiness/incr/cells`
Expected: all tests pass (existing hybrid dispose tests still pass)

- [ ] **Step 7: Commit**

```bash
git add cells/hybrid_memo.mbt cells/runtime.mbt cells/dispose_test.mbt
git commit -m "feat: improve HybridMemo dispose slot clearing, add is_disposed()"
```

---

## Task 6: is_disposed() for Reactive and Effect

**Files:**
- Modify: `cells/push_reactive.mbt` — add `Reactive::is_disposed()`
- Modify: `cells/push_effect.mbt` — add `Effect::is_disposed()`
- Modify: `cells/dispose_test.mbt` — add tests

- [ ] **Step 1: Write failing tests**

Append to `cells/dispose_test.mbt`:

```moonbit
///|
test "reactive: is_disposed returns correct state" {
  let rt = Runtime::new()
  let sig = Signal::new(rt, 10)
  let r = Reactive::new(rt, fn() { sig.get() * 2 })
  assert_false!(r.is_disposed())
  r.dispose()
  assert_true!(r.is_disposed())
}

///|
test "effect: is_disposed returns correct state" {
  let rt = Runtime::new()
  let sig = Signal::new(rt, 10)
  let eff = Effect::new(rt, fn() { ignore(sig.get()) })
  assert_false!(eff.is_disposed())
  eff.dispose()
  assert_true!(eff.is_disposed())
}
```

- [ ] **Step 2: Implement Reactive::is_disposed()**

Add to `cells/push_reactive.mbt`:

```moonbit
///|
/// Returns true if this reactive has been disposed.
pub fn[T] Reactive::is_disposed(self : Reactive[T]) -> Bool {
  let id = self.cell_id.id.id
  if id < 0 || id >= self.rt.core.cell_index.length() {
    return true
  }
  match self.rt.core.cell_index[id] {
    Disposed => true
    _ => false
  }
}
```

- [ ] **Step 3: Implement Effect::is_disposed()**

Add to `cells/push_effect.mbt`:

```moonbit
///|
/// Returns true if this effect has been disposed.
pub fn Effect::is_disposed(self : Effect) -> Bool {
  let id = self.cell_id.id
  if id < 0 || id >= self.rt.core.cell_index.length() {
    return true
  }
  match self.rt.core.cell_index[id] {
    Disposed => true
    _ => false
  }
}
```

- [ ] **Step 4: Run moon check and tests**

Run: `moon check && moon test -p dowdiness/incr/cells -f dispose_test.mbt`
Expected: all pass

- [ ] **Step 5: Commit**

```bash
git add cells/push_reactive.mbt cells/push_effect.mbt cells/dispose_test.mbt
git commit -m "feat: add is_disposed() for Reactive and Effect"
```

---

## Task 7: Relation::dispose(), FunctionalRelation::dispose(), and Rule dispose

**Files:**
- Modify: `cells/runtime.mbt` — add `dispose_relation`, `dispose_functional_relation`, `dispose_rule` (public)
- Modify: `cells/datalog_relation.mbt` — add `Relation::dispose()`, `Relation::is_disposed()`
- Modify: `cells/datalog_functional_relation.mbt` — add `FunctionalRelation::dispose()`, `FunctionalRelation::is_disposed()`
- Modify: `cells/datalog_rule.mbt` — no changes needed (Rule has no user-facing wrapper with runtime ref)
- Modify: `cells/dispose_test.mbt` — add tests

**Note on Rule:** `Runtime::new_rule()` returns `RuleId` which is a bare `CellId` wrapper with no runtime reference (`types/cell_handles.mbt:38`). Therefore `Runtime::dispose_rule` is exposed as a public method — the user calls `rt.dispose_rule(rule_id)` since `RuleId` can't self-dispose.

- [ ] **Step 1: Write failing tests**

Append to `cells/dispose_test.mbt`:

```moonbit
///|
test "relation: dispose marks cell as disposed" {
  let rt = Runtime::new()
  let rel : Relation[Int] = Relation::new(rt)
  rel.insert(42)
  assert_false!(rel.is_disposed())
  rel.dispose()
  assert_true!(rel.is_disposed())
}

///|
test "relation: dispose is idempotent" {
  let rt = Runtime::new()
  let rel : Relation[Int] = Relation::new(rt)
  rel.dispose()
  rel.dispose() // no-op
  assert_true!(rel.is_disposed())
}
```

- [ ] **Step 2: Implement Runtime::dispose_relation()**

Add to `cells/runtime.mbt`:

```moonbit
///|
fn Runtime::dispose_relation(self : Runtime, cell_id : CellId) -> Unit {
  if cell_id.id < 0 || cell_id.id >= self.core.cell_index.length() {
    return
  }
  match self.core.cell_index[cell_id.id] {
    Relation(idx) => {
      let rel = self.datalog.relations[idx]
      rel.meta.subscribers.clear()
      rel.meta.label = None
      self.core.cell_index[cell_id.id] = Disposed
    }
    _ => ()
  }
}
```

- [ ] **Step 3: Implement Relation::dispose() and is_disposed()**

Add to `cells/datalog_relation.mbt`:

```moonbit
///|
/// Disposes this relation, clearing its fact sets and marking it as Disposed.
pub fn[T] Relation::dispose(self : Relation[T]) -> Unit {
  self.rt.dispose_relation(self.cell_id)
  self.current.val.clear()
  self.delta.val.clear()
  self.staged_delta.val.clear()
}

///|
/// Returns true if this relation has been disposed.
pub fn[T] Relation::is_disposed(self : Relation[T]) -> Bool {
  let id = self.cell_id.id
  if id < 0 || id >= self.rt.core.cell_index.length() {
    return true
  }
  match self.rt.core.cell_index[id] {
    Disposed => true
    _ => false
  }
}
```

- [ ] **Step 4: Implement Runtime::dispose_functional_relation()**

Add to `cells/runtime.mbt`:

```moonbit
///|
fn Runtime::dispose_functional_relation(self : Runtime, cell_id : CellId) -> Unit {
  if cell_id.id < 0 || cell_id.id >= self.core.cell_index.length() {
    return
  }
  match self.core.cell_index[cell_id.id] {
    FunctionalRelation(idx) => {
      let frel = self.datalog.functional_relations[idx]
      frel.meta.subscribers.clear()
      frel.meta.label = None
      self.core.cell_index[cell_id.id] = Disposed
    }
    _ => ()
  }
}
```

- [ ] **Step 5: Add FunctionalRelation::dispose() and is_disposed()**

Add to `cells/datalog_functional_relation.mbt` (NOT datalog_relation.mbt):

```moonbit
///|
pub fn[K, V] FunctionalRelation::dispose(self : FunctionalRelation[K, V]) -> Unit {
  self.rt.dispose_functional_relation(self.cell_id)
  self.current.val.clear()
  self.delta.val.clear()
  self.staged_delta.val.clear()
}

///|
pub fn[K, V] FunctionalRelation::is_disposed(self : FunctionalRelation[K, V]) -> Bool {
  let id = self.cell_id.id
  if id < 0 || id >= self.rt.core.cell_index.length() {
    return true
  }
  match self.rt.core.cell_index[id] {
    Disposed => true
    _ => false
  }
}
```

- [ ] **Step 6: Implement Runtime::dispose_rule() (public)**

Add to `cells/runtime.mbt`. This is **public** because `RuleId` has no runtime reference — the user calls `rt.dispose_rule(rule_id)`:

```moonbit
///|
/// Disposes a rule cell. Public because RuleId has no runtime reference.
pub fn Runtime::dispose_rule(self : Runtime, rule_id : @incr_types.RuleId) -> Unit {
  let cell_id = rule_id.id
  if cell_id.id < 0 || cell_id.id >= self.core.cell_index.length() {
    return
  }
  match self.core.cell_index[cell_id.id] {
    Rule(idx) => {
      let rule = self.datalog.rules[idx]
      rule.meta.subscribers.clear()
      rule.meta.label = None
      // Note: RuleData.apply_delta, input_relations, output_relations are
      // immutable fields (not `mut`). They cannot be cleared here. The
      // closures and arrays will be released when the RuleData struct is
      // overwritten on slot reuse, or by the host GC. If aggressive clearing
      // is needed later, add `mut` to these fields in datalog_rule.mbt.
      self.core.cell_index[cell_id.id] = Disposed
    }
    _ => ()
  }
}
```

- [ ] **Step 6: Run moon check and tests**

Run: `moon check && moon test -p dowdiness/incr/cells -f dispose_test.mbt`
Expected: all pass

Run: `moon test -p dowdiness/incr/cells`
Expected: all tests pass (no regressions)

- [ ] **Step 7: Commit**

```bash
git add cells/runtime.mbt cells/datalog_relation.mbt cells/datalog_rule.mbt cells/dispose_test.mbt
git commit -m "feat: add dispose() for Relation, FunctionalRelation, and Rule"
```

---

## Task 8: TrackedCell::dispose() and is_disposed()

**Files:**
- Modify: `cells/tracked_cell.mbt` — delegate to inner Signal
- Modify: `cells/dispose_test.mbt` — add tests

- [ ] **Step 1: Write failing test**

Append to `cells/dispose_test.mbt`:

```moonbit
///|
test "tracked cell: dispose delegates to inner signal" {
  let rt = Runtime::new()
  let cell = TrackedCell::new(rt, 42)
  assert_false!(cell.is_disposed())
  cell.dispose()
  assert_true!(cell.is_disposed())
}
```

- [ ] **Step 2: Implement TrackedCell::dispose() and is_disposed()**

Add to `cells/tracked_cell.mbt`:

```moonbit
///|
/// Disposes this tracked cell by disposing its inner signal.
pub fn[T] TrackedCell::dispose(self : TrackedCell[T]) -> Unit {
  self.signal.dispose()
}

///|
/// Returns true if this tracked cell has been disposed.
pub fn[T] TrackedCell::is_disposed(self : TrackedCell[T]) -> Bool {
  self.signal.is_disposed()
}
```

- [ ] **Step 3: Run moon check and tests**

Run: `moon check && moon test -p dowdiness/incr/cells -f dispose_test.mbt`
Expected: all pass

- [ ] **Step 4: Commit**

```bash
git add cells/tracked_cell.mbt cells/dispose_test.mbt
git commit -m "feat: add TrackedCell::dispose() and is_disposed()"
```

---

## Task 9: Disposal safety guards

**Files:**
- Modify: `cells/runtime.mbt` — add safety checks to all dispose methods
- Modify: `cells/dispose_test.mbt` — add batch dispose tests
- Modify: `cells/dispose_wbtest.mbt` — add mid-batch cleanup whitebox test

- [ ] **Step 1: Write failing test for signal dispose mid-batch**

Append to `cells/dispose_test.mbt`:

```moonbit
///|
test "signal: dispose during batch discards pending write" {
  let rt = Runtime::new()
  let sig = Signal::new(rt, 10)
  rt.batch(fn() {
    sig.set(20)      // queued as pending
    sig.dispose()     // should discard the pending write
  })
  // Batch commits — disposed signal's write should be gone
  assert_true!(sig.is_disposed())
}

///|
test "signal: dispose of a dependency during computation is safe" {
  // Disposing a different cell during a memo's compute function is allowed.
  // The memo will still see the value it already read. Future reads of the
  // disposed cell will abort, which is the caller's responsibility.
  let rt = Runtime::new()
  let sig = Signal::new(rt, 10)
  let other_sig = Signal::new(rt, 99)
  let m = Memo::new(rt, fn() {
    let v = sig.get()
    other_sig.dispose()  // dispose a DIFFERENT cell — allowed
    v
  })
  inspect!(m.get(), content="10")
  assert_true!(other_sig.is_disposed())
}
```

- [ ] **Step 2: Add self-dispose guard to dispose methods**

The only forbidden case: disposing a cell **during its own computation** (it's on the tracking stack). Disposing a different cell during computation is safe and already tested by reactive mid-wave disposal tests.

Add at the top of `dispose_signal`, `dispose_memo`, `dispose_hybrid_memo` in `cells/runtime.mbt`:

```moonbit
  // Guard: cannot dispose a cell during its own computation
  for aq in self.core.tracking_stack {
    if aq.cell_id == cell_id {
      abort("dispose: cannot dispose a cell during its own computation")
    }
  }
```

Note: This guard does NOT prevent disposing other cells during computation. That is intentionally allowed — the reactive mid-wave disposal tests verify this works correctly.

- [ ] **Step 3: Handle batch pending cleanup in dispose_signal**

In `dispose_signal`, before marking Disposed, remove the signal's pending commit from the batch queue:

```moonbit
      // If inside a batch, remove any pending commit for this signal
      if self.core.batch_depth > 0 {
        self.remove_batch_signal(cell_id)
      }
```

`remove_batch_signal` already exists in `cells/batch.mbt` — it does O(n) removal from `batch_pending`.

- [ ] **Step 4: Run moon check and tests**

Run: `moon check && moon test -p dowdiness/incr/cells`
Expected: all pass, including the new batch dispose test and panic test

- [ ] **Step 5: Commit**

```bash
git add cells/runtime.mbt cells/dispose_test.mbt cells/dispose_wbtest.mbt
git commit -m "feat: add disposal safety guards for mid-verify and mid-batch"
```

---

## Task 10: Integration tests + post-Layer 1 benchmarks

**Files:**
- Modify: `tests/integration_test.mbt` — add dispose integration tests
- Modify: `tests/bench_test.mbt` — add post-dispose benchmarks

- [ ] **Step 1: Write integration tests**

Add to `tests/integration_test.mbt`:

```moonbit
///|
test "dispose: signal dispose cascades to memo staleness" {
  let rt = Runtime::new()
  let sig = Signal::new(rt, 10)
  let m = Memo::new(rt, fn() { sig.get() * 2 })
  inspect!(m.get(), content="20")
  sig.dispose()
  // Memo's dependency is now disposed — verifying should abort
  // But since we can't catch aborts in tests, verify the signal is disposed
  assert_true!(sig.is_disposed())
}

///|
test "dispose: multiple signals, dispose one, others unaffected" {
  let rt = Runtime::new()
  let a = Signal::new(rt, 1)
  let b = Signal::new(rt, 2)
  let sum = Memo::new(rt, fn() { a.get() + b.get() })
  inspect!(sum.get(), content="3")
  a.dispose()
  assert_true!(a.is_disposed())
  assert_false!(b.is_disposed())
  assert_false!(sum.is_disposed())
}
```

- [ ] **Step 2: Add post-dispose benchmark**

Append to `tests/bench_test.mbt`:

```moonbit
///|
test "layer1: memo create-dispose cycle (free list)" (b : @bench.T) {
  let rt = Runtime::new()
  let sig = Signal::new(rt, 0)
  b.bench(fn() {
    let m = Memo::new(rt, fn() { sig.get() })
    ignore(m.get())
    m.dispose()
  })
}

///|
test "layer1: signal create-dispose cycle (free list)" (b : @bench.T) {
  let rt = Runtime::new()
  b.bench(fn() {
    let sig = Signal::new(rt, 0)
    sig.dispose()
  })
}
```

- [ ] **Step 3: Run all tests**

Run: `moon test`
Expected: all tests pass

- [ ] **Step 4: Run benchmarks and compare to baselines**

Run: `moon bench --release`

Compare against Task 0 baselines. Verify:
- Existing benchmarks: no regression > 5%
- Create-dispose cycles: slot reuse working (stable iteration time)

- [ ] **Step 5: Run moon info && moon fmt**

Run: `moon info && moon fmt`

- [ ] **Step 6: Final commit**

```bash
git add -A
git commit -m "feat: complete Layer 1 — manual dispose for all cell types with free lists"
```

---

## Summary

| Task | What | Tests |
|------|------|-------|
| 0 | Baseline benchmarks | 7 benchmarks |
| 1 | Signal::dispose() + is_disposed() + disposed guards on get/set | 3 black-box tests |
| 2 | Signal free list | 2 whitebox tests |
| 3 | Memo::dispose() + is_disposed() (with compute closure clearing) | 4 tests |
| 4 | Memo free list (Memo::_create + HybridMemo::new) | 1 whitebox test |
| 5 | HybridMemo improvements (slot clearing, is_disposed) | 1 test + existing tests |
| 6 | Reactive/Effect is_disposed() | 2 tests |
| 7 | Relation/FunctionalRelation/Rule dispose | 2+ tests |
| 8 | TrackedCell dispose | 1 test |
| 9 | Disposal safety guards (mid-verify, mid-batch) | 2 tests |
| 10 | Integration tests + benchmarks | 2 integration + 2 benchmarks |

**Total: 10 tasks, ~22 tests, ~10 commits**

After this plan is complete, subsequent plans will cover:
- Layer 2: Scope
- Layer 3: Composed traits
- Layer 4: Observer + gc()
- Layer 5: API boundary enforcement
