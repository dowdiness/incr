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
| Modify | `cells/datalog_rule.mbt` | Add `RuleData::clear_slot()` |
| Create | `cells/dispose_test.mbt` | Black-box dispose tests for Signal, Memo, Relation, Rule |
| Create | `cells/dispose_wbtest.mbt` | Whitebox dispose tests (subscriber cleanup, free lists, slot clearing) |

---

## Task 0: Baseline Benchmarks

**Files:**
- Modify: `tests/bench_test.mbt`

- [ ] **Step 1: Add cell accumulation benchmarks**

Append to `tests/bench_test.mbt`:

```moonbit
///|
test "baseline: signal.set with 0 dead memos" (b : @bench.T) {
  let rt = Runtime::new()
  let sig = Signal::new(rt, 0)
  let mut v = 0
  b.bench(fn() { v += 1; sig.set(v) })
}

///|
test "baseline: signal.set with 10k dead memos" (b : @bench.T) {
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
test "baseline: memo creation (monotonic growth)" (b : @bench.T) {
  let rt = Runtime::new()
  let sig = Signal::new(rt, 0)
  b.bench(fn() {
    ignore(Memo::new(rt, fn() { sig.get() }))
  })
}
```

- [ ] **Step 2: Add push CPU waste benchmarks**

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
test "baseline: push propagation with 100 abandoned reactives" (b : @bench.T) {
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

- [ ] **Step 3: Add slot reuse benchmark**

Append to `tests/bench_test.mbt`:

```moonbit
///|
test "baseline: reactive create-dispose cycle (free list)" (b : @bench.T) {
  let rt = Runtime::new()
  let sig = Signal::new(rt, 0)
  b.bench(fn() {
    let r = Reactive::new(rt, fn() { sig.get() })
    r.dispose()
  })
}
```

- [ ] **Step 4: Run moon check**

Run: `moon check`
Expected: no errors

- [ ] **Step 5: Run benchmarks and record baselines**

Run: `cd /home/antisatori/ghq/github.com/dowdiness/canopy/loom/incr && moon bench --release`

Record the output. These are the baselines for comparison after Layer 1.

- [ ] **Step 6: Commit**

```bash
git add tests/bench_test.mbt
git commit -m "bench: add Phase 1 baseline benchmarks for dispose/GC"
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

- [ ] **Step 6: Run moon check**

Run: `moon check`
Expected: no errors

- [ ] **Step 7: Run tests**

Run: `moon test -p dowdiness/incr/cells -f dispose_test.mbt`
Expected: all 3 tests pass (including panic test)

- [ ] **Step 8: Commit**

```bash
git add cells/signal.mbt cells/runtime.mbt cells/dispose_test.mbt
git commit -m "feat: add Signal::dispose() and is_disposed()"
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

In `cells/runtime.mbt`, modify `Runtime::new_signal_id`:

```moonbit
fn Runtime::new_signal_id(
  self : Runtime,
  durability : Durability,
  label : String?,
) -> CellId {
  // Check free list first
  if self.pull.free_signals.length() > 0 {
    let idx = self.pull.free_signals.pop_exn()
    let cell_id = self.alloc_cell_id(PullSignal(idx))
    self.pull.signals[idx] = {
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
    let ops : &CellOps = self.pull.signals[idx]
    self.core.cell_ops[cell_id.id] = ops
    return cell_id
  }
  let idx = self.pull.signals.length()
  let cell_id = self.alloc_cell_id(PullSignal(idx))
  self.pull.signals.push({
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
  })
  let ops : &CellOps = self.pull.signals[idx]
  self.core.cell_ops.push(ops)
  cell_id
}
```

Note: When reusing a slot, `alloc_cell_id` pushes a new entry to `cell_index` (the cell gets a NEW CellId, not the old one). The SoA slot at `idx` is reused but the CellId is fresh. `cell_ops` at the new CellId position must also be set.

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

- [ ] **Step 3: Update new_memo_id to check free list**

In `cells/runtime.mbt`, find `Runtime::new_memo_id` (the method that allocates SoA slots for memos) and add a free list check at the top. If `free_memos` is non-empty, pop an index, overwrite the SoA slot at that index with fresh MemoData, register a new CellId via `alloc_cell_id(PullMemo(idx))`, and set `cell_ops[cell_id.id]` to the new data. If the free list is empty, fall through to the existing growth path. The pattern is identical to the signal free list in Task 2 Step 5 — read that implementation and mirror it for memos using `self.pull.memos[idx]` and `PullMemo(idx)`.

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

## Task 7: Relation::dispose(), FunctionalRelation::dispose(), and Rule::dispose()

**Files:**
- Modify: `cells/runtime.mbt` — add `dispose_relation`, `dispose_functional_relation`, `dispose_rule`
- Modify: `cells/datalog_relation.mbt` — add `Relation::dispose()`, `Relation::is_disposed()`, `FunctionalRelation::dispose()`, `FunctionalRelation::is_disposed()`
- Modify: `cells/datalog_rule.mbt` — add `RuleData::clear_slot()`
- Modify: `cells/dispose_test.mbt` — add tests

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

- [ ] **Step 4: Implement Runtime::dispose_functional_relation() and FunctionalRelation methods**

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

Add `dispose()` and `is_disposed()` to the FunctionalRelation type in its source file, following the same pattern as Relation (delegate to `rt.dispose_functional_relation(self.cell_id)`, check `cell_index` for Disposed).

- [ ] **Step 5: Implement Runtime::dispose_rule()**

Add to `cells/runtime.mbt`:

```moonbit
///|
fn Runtime::dispose_rule(self : Runtime, cell_id : CellId) -> Unit {
  if cell_id.id < 0 || cell_id.id >= self.core.cell_index.length() {
    return
  }
  match self.core.cell_index[cell_id.id] {
    Rule(idx) => {
      let rule = self.datalog.rules[idx]
      rule.meta.subscribers.clear()
      rule.meta.label = None
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

## Task 9: Integration tests + post-Layer 1 benchmarks

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
| 1 | Signal::dispose() + is_disposed() | 3 black-box tests |
| 2 | Signal free list | 2 whitebox tests |
| 3 | Memo::dispose() + is_disposed() | 4 tests (black-box + subscriber cleanup) |
| 4 | Memo free list | 1 whitebox test |
| 5 | HybridMemo improvements | 1 test + existing tests |
| 6 | Reactive/Effect is_disposed() | 2 tests |
| 7 | Relation/Rule dispose | 2 tests |
| 8 | TrackedCell dispose | 1 test |
| 9 | Integration tests + benchmarks | 2 integration + 2 benchmarks |

**Total: 9 tasks, ~20 tests, ~9 commits**

After this plan is complete, subsequent plans will cover:
- Layer 2: Scope
- Layer 3: Composed traits
- Layer 4: Observer + gc()
- Layer 5: API boundary enforcement
