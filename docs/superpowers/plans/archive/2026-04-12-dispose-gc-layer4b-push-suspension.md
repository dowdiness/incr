# Layer 4b: Push Suspension Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Fill in `on_observe`/`on_unobserve` for PushReactive, add `Scope::add_observer`, add `MemoMap::sweep`.

**Architecture:** Gate `on_observe` to the 0→1 observer transition in all `observe()` methods. PushReactive suspends (unsubscribes from sources) when last observer leaves AND subscriber set is empty. Reactivates via full recompute on first observer. HybridMemo/PullMemo remain no-ops. `Scope::add_observer` registers an Observer's dispose closure. `MemoMap::sweep` removes disposed entries after gc().

**Tech Stack:** MoonBit, `moon test`, `moon check`

**Spec:** `docs/superpowers/specs/2026-04-12-dispose-gc-layer4b-push-suspension.md`

---

### Task 1: Gate on_observe to 0→1 transition

**Files:**
- Modify: `cells/runtime.mbt:662-669` (`add_gc_root`)
- Modify: `cells/observer.mbt:60-108` (three `observe()` methods)
- Test: `cells/observer_test.mbt`

- [ ] **Step 1: Write failing test — on_observe fires only on 0→1 transition**

Add to `cells/observer_test.mbt`:

```moonbit
///|
test "observer: on_observe fires only on 0-to-1 transition" {
  let rt = Runtime::new()
  let sig = Signal::new(rt, 10)
  let r = Reactive::new(rt, fn() { sig.get() * 2 })
  // First observer: 0→1 transition
  let obs1 = r.observe()
  inspect(obs1.get(), content="20")
  // Second observer: 1→2 transition — on_observe should NOT fire again
  let obs2 = r.observe()
  inspect(obs2.get(), content="20")
  obs1.dispose()
  inspect(obs2.get(), content="20")
  obs2.dispose()
}
```

Run: `moon test -p dowdiness/incr/cells -f observer_test.mbt`
Expected: PASS (this test passes with current code since on_observe is a no-op, establishing baseline)

- [ ] **Step 2: Change `add_gc_root` to return previous count**

In `cells/runtime.mbt`, replace lines 662-669:

```moonbit
///|
/// Increments the observer reference count for a cell.
/// Returns the previous count (0 means this is the first observer).
fn Runtime::add_gc_root(self : Runtime, id : CellId) -> Int {
  match self.core.gc_root_counts.get(id) {
    Some(n) => {
      self.core.gc_root_counts.set(id, n + 1)
      n
    }
    None => {
      self.core.gc_root_counts.set(id, 1)
      0
    }
  }
}
```

Run: `moon check`
Expected: Errors in `observer.mbt` — `add_gc_root` return type changed from `Unit` to `Int`, callers don't use the value yet.

- [ ] **Step 3: Update observe() methods to gate on_observe**

In `cells/observer.mbt`, replace `Memo::observe` (lines 60-73):

```moonbit
///|
/// Creates an observer for a Memo cell.
pub fn[T] Memo::observe(self : Memo[T]) -> Observer[T] {
  guard !self.rt.is_cell_disposed(self.cell_id) else {
    abort("Memo::observe called on a disposed memo")
  }
  let rt = self.rt
  let prev = rt.add_gc_root(self.cell_id)
  if prev == 0 {
    rt.core.cell_lifecycle[self.cell_id.id].on_observe(rt, self.cell_id)
  }
  {
    runtime: rt,
    target_id: self.cell_id,
    getter: fn() { self.get() },
    disposed: false,
  }
}
```

Replace `HybridMemo::observe` (lines 77-90):

```moonbit
///|
/// Creates an observer for a HybridMemo cell.
pub fn[T : Eq] HybridMemo::observe(self : HybridMemo[T]) -> Observer[T] {
  guard !self.rt.is_cell_disposed(self.cell_id) else {
    abort("HybridMemo::observe called on a disposed hybrid memo")
  }
  let rt = self.rt
  let prev = rt.add_gc_root(self.cell_id)
  if prev == 0 {
    rt.core.cell_lifecycle[self.cell_id.id].on_observe(rt, self.cell_id)
  }
  {
    runtime: rt,
    target_id: self.cell_id,
    getter: fn() { self.get() },
    disposed: false,
  }
}
```

Replace `Reactive::observe` (lines 94-108):

```moonbit
///|
/// Creates an observer for a Reactive cell.
pub fn[T] Reactive::observe(self : Reactive[T]) -> Observer[T] {
  let cell_id = self.cell_id.id
  guard !self.rt.is_cell_disposed(cell_id) else {
    abort("Reactive::observe called on a disposed reactive")
  }
  let rt = self.rt
  let prev = rt.add_gc_root(cell_id)
  if prev == 0 {
    rt.core.cell_lifecycle[cell_id.id].on_observe(rt, cell_id)
  }
  {
    runtime: rt,
    target_id: cell_id,
    getter: fn() { self.get() },
    disposed: false,
  }
}
```

- [ ] **Step 4: Run tests to verify nothing breaks**

Run: `moon check && moon test -p dowdiness/incr/cells`
Expected: All existing tests pass. `add_gc_root` return value is used; on_observe gating is transparent since all impls are still no-ops.

- [ ] **Step 5: Commit**

```bash
git add cells/runtime.mbt cells/observer.mbt
git commit -m "refactor: gate on_observe to 0→1 observer transition

add_gc_root now returns the previous count. All three observe()
methods only call on_observe when the count transitions 0→1,
symmetric with on_unobserve's 1→0 transition. Prepares for
Layer 4b push suspension where on_observe triggers a recompute."
```

---

### Task 2: Implement PushReactiveData::on_unobserve

**Files:**
- Modify: `cells/push_reactive.mbt:52-65` (add `on_unobserve` impl after existing `dispose_cell`)
- Test: `cells/observer_test.mbt`

- [ ] **Step 1: Write failing test — suspension removes subscriber links**

Add to `cells/observer_test.mbt`:

```moonbit
///|
test "observer: reactive suspends on last observer removal when no subscribers" {
  let rt = Runtime::new()
  let sig = Signal::new(rt, 10)
  let r = Reactive::new(rt, fn() { sig.get() * 2 })
  let obs = r.observe()
  inspect(obs.get(), content="20")
  // Signal has reactive in subscriber set
  inspect(rt.get_subscribers(sig.id()).count(), content="1")
  obs.dispose()
  // After last observer removed and no subscribers: reactive suspended
  // Signal's subscriber set should be empty (reactive unsubscribed)
  inspect(rt.get_subscribers(sig.id()).count(), content="0")
}
```

Run: `moon test -p dowdiness/incr/cells -f observer_test.mbt -i 8`
Expected: FAIL — after `obs.dispose()`, subscriber count is still `1` (on_unobserve is a no-op).

- [ ] **Step 2: Implement on_unobserve**

In `cells/push_reactive.mbt`, add after the `dispose_cell` impl (after line 65):

```moonbit
///|
/// Suspends the push path when the last observer is removed.
///
/// Only suspends if no other cell reads this reactive (subscribers empty).
/// A Memo or another Reactive in the subscriber set means this cell's
/// changed_at must keep advancing — suspension would cause stale reads.
impl CellLifecycle for PushReactiveData with on_unobserve(self, rt, cell_id) {
  guard self.meta.subscribers.is_empty() else { return }
  for source in self.sources {
    rt.remove_subscriber(source, cell_id)
  }
}
```

- [ ] **Step 3: Run tests**

Run: `moon check && moon test -p dowdiness/incr/cells -f observer_test.mbt`
Expected: All pass, including the new test — subscriber count is 0 after dispose.

- [ ] **Step 4: Write test — subscribers prevent suspension**

Add to `cells/observer_test.mbt`:

```moonbit
///|
test "observer: reactive does NOT suspend when it has subscribers" {
  let rt = Runtime::new()
  let sig = Signal::new(rt, 10)
  let r = Reactive::new(rt, fn() { sig.get() * 2 })
  // Memo reads the reactive — creates a subscriber link
  let m = Memo::new(rt, fn() { r.get() + 1 })
  let obs_m = m.observe()
  ignore(obs_m.get())
  // Observe and unobserve the reactive itself
  let obs_r = r.observe()
  ignore(obs_r.get())
  obs_r.dispose()
  // Reactive still has m in its subscriber set — must NOT suspend
  inspect(rt.get_subscribers(sig.id()).count(), content="1")
  // Push propagation still works through to the memo
  sig.set(20)
  inspect(obs_m.get(), content="41")
  obs_m.dispose()
}
```

Run: `moon test -p dowdiness/incr/cells -f observer_test.mbt`
Expected: PASS

- [ ] **Step 5: Commit**

```bash
git add cells/push_reactive.mbt cells/observer_test.mbt
git commit -m "feat: implement PushReactiveData::on_unobserve

Suspends push path by unsubscribing from all sources when last
observer is removed AND subscriber set is empty. Guards against
suspension when downstream cells (push or pull) still read this
reactive — their changed_at checking depends on push propagation."
```

---

### Task 3: Implement PushReactiveData::on_observe

**Files:**
- Modify: `cells/push_reactive.mbt` (add `on_observe` impl)
- Test: `cells/observer_test.mbt`

- [ ] **Step 1: Write failing test — reactivation catches up on missed changes**

Add to `cells/observer_test.mbt`:

```moonbit
///|
test "observer: reactive reactivation catches up on missed changes" {
  let rt = Runtime::new()
  let sig = Signal::new(rt, 10)
  let r = Reactive::new(rt, fn() { sig.get() * 2 })
  // Observe, verify, unobserve
  let obs1 = r.observe()
  inspect(obs1.get(), content="20")
  obs1.dispose()
  // Signal changes while reactive is suspended
  sig.set(50)
  // Re-observe — should see updated value
  let obs2 = r.observe()
  inspect(obs2.get(), content="100")
  obs2.dispose()
}
```

Run: `moon test -p dowdiness/incr/cells -f observer_test.mbt`
Expected: FAIL — after re-observe, `obs2.get()` returns `20` (stale cached value; on_observe is a no-op).

- [ ] **Step 2: Implement on_observe**

In `cells/push_reactive.mbt`, add after the `on_unobserve` impl:

```moonbit
///|
/// Activates the push path when the first observer is added.
///
/// Recomputes with fresh tracking to establish current sources and
/// a correct cached value. Passes [] as old_sources because subscriber
/// links were removed during suspension. For fresh cells (never
/// suspended), add_subscriber is idempotent.
impl CellLifecycle for PushReactiveData with on_observe(self, rt, cell_id) {
  guard !rt.core.in_push_propagation else {
    abort("on_observe: cannot activate during push propagation")
  }
  guard !rt.core.in_fixpoint else {
    abort("on_observe: cannot activate during fixpoint evaluation")
  }
  rt.begin_tracking(cell_id)
  let _ = (self.compute)()
  let new_sources = rt.end_tracking()
  rt.finish_tracking(cell_id, [], new_sources)
  self.sources = new_sources
  self.level = rt.recompute_level(cell_id, new_sources)
  self.dirty = false
}
```

- [ ] **Step 3: Run tests**

Run: `moon check && moon test -p dowdiness/incr/cells -f observer_test.mbt`
Expected: All pass, including the reactivation test.

- [ ] **Step 4: Write test — repeated suspend/activate cycles**

Add to `cells/observer_test.mbt`:

```moonbit
///|
test "observer: repeated suspend/activate cycles" {
  let rt = Runtime::new()
  let sig = Signal::new(rt, 1)
  let r = Reactive::new(rt, fn() { sig.get() * 10 })
  // Cycle 1
  let obs1 = r.observe()
  inspect(obs1.get(), content="10")
  obs1.dispose()
  sig.set(2)
  // Cycle 2
  let obs2 = r.observe()
  inspect(obs2.get(), content="20")
  obs2.dispose()
  sig.set(3)
  // Cycle 3
  let obs3 = r.observe()
  inspect(obs3.get(), content="30")
  obs3.dispose()
}
```

- [ ] **Step 5: Write test — multiple observers ref-counting with suspension**

Add to `cells/observer_test.mbt`:

```moonbit
///|
test "observer: multiple observers prevent suspension until last disposed" {
  let rt = Runtime::new()
  let sig = Signal::new(rt, 5)
  let r = Reactive::new(rt, fn() { sig.get() + 1 })
  let obs1 = r.observe()
  let obs2 = r.observe()
  inspect(obs1.get(), content="6")
  // Dispose first — on_unobserve should NOT fire (count 2→1)
  obs1.dispose()
  // Push still works
  sig.set(10)
  inspect(obs2.get(), content="11")
  // Dispose second — on_unobserve fires (count 1→0), suspend
  obs2.dispose()
  inspect(rt.get_subscribers(sig.id()).count(), content="0")
  // Re-observe catches up
  sig.set(20)
  let obs3 = r.observe()
  inspect(obs3.get(), content="21")
  obs3.dispose()
}
```

- [ ] **Step 6: Run all tests**

Run: `moon test -p dowdiness/incr/cells -f observer_test.mbt`
Expected: All pass.

- [ ] **Step 7: Commit**

```bash
git add cells/push_reactive.mbt cells/observer_test.mbt
git commit -m "feat: implement PushReactiveData::on_observe

Full recompute with fresh tracking on first observer (0→1 transition).
Establishes current sources and correct cached value. Guards against
activation during push propagation and fixpoint evaluation."
```

---

### Task 4: Edge case tests for push suspension

**Files:**
- Test: `cells/observer_test.mbt`
- Test: `cells/gc_test.mbt`

- [ ] **Step 1: Write test — GC of suspended reactive**

Add to `cells/gc_test.mbt`:

```moonbit
///|
test "gc: collects suspended reactive" {
  let rt = Runtime::new()
  let sig = Signal::new(rt, 1)
  let r = Reactive::new(rt, fn() { sig.get() * 2 })
  // Observe then unobserve — reactive is suspended
  let obs = r.observe()
  ignore(obs.get())
  obs.dispose()
  // gc should collect it (Interior, unreachable)
  rt.gc()
  assert_true(r.is_disposed())
}
```

- [ ] **Step 2: Write test — dispose during suspension is idempotent**

Add to `cells/observer_test.mbt`:

```moonbit
///|
test "observer: dispose suspended reactive is idempotent" {
  let rt = Runtime::new()
  let sig = Signal::new(rt, 1)
  let r = Reactive::new(rt, fn() { sig.get() })
  let obs = r.observe()
  ignore(obs.get())
  obs.dispose()
  // Reactive is suspended — subscriber links already removed
  // Manual dispose should not double-decrement or abort
  r.dispose()
  assert_true(r.is_disposed())
  assert_false(sig.is_disposed())
}
```

- [ ] **Step 3: Write test — source disposal during suspension**

Add to `cells/observer_test.mbt`:

```moonbit
///|
test "observer: source disposed during suspension — reactivation uses fresh sources" {
  let rt = Runtime::new()
  let sig1 = Signal::new(rt, 10)
  let sig2 = Signal::new(rt, 20)
  let use_sig1 : Ref[Bool] = { val: true }
  let r = Reactive::new(rt, fn() {
    if use_sig1.val { sig1.get() } else { sig2.get() }
  })
  let obs = r.observe()
  inspect(obs.get(), content="10")
  obs.dispose()
  // Switch source and change values while suspended
  use_sig1.val = false
  sig1.set(99)
  sig2.set(42)
  // Re-observe — recompute picks up sig2 as new source
  let obs2 = r.observe()
  inspect(obs2.get(), content="42")
  obs2.dispose()
}
```

- [ ] **Step 4: Write test — pull subscriber with HybridMemo prevents suspension**

Add to `cells/observer_test.mbt`:

```moonbit
///|
test "observer: hybrid memo reading reactive prevents suspension" {
  let rt = Runtime::new()
  let sig = Signal::new(rt, 5)
  let r = Reactive::new(rt, fn() { sig.get() * 3 })
  let h = HybridMemo::new(rt, fn() { r.get() + 1 })
  let obs_h = h.observe()
  ignore(obs_h.get())
  // Observe and unobserve the reactive
  let obs_r = r.observe()
  ignore(obs_r.get())
  obs_r.dispose()
  // Reactive has h in its subscriber set — must NOT suspend
  sig.set(10)
  inspect(obs_h.get(), content="31")
  obs_h.dispose()
}
```

- [ ] **Step 5: Write panic test — on_observe during fixpoint aborts**

Add to `cells/observer_test.mbt`:

```moonbit
///|
test "panic observer: on_observe during fixpoint aborts" {
  let rt = Runtime::new()
  let sig = Signal::new(rt, 1)
  let r = Reactive::new(rt, fn() { sig.get() })
  let rel = Relation::new(rt)
  rel.insert(1)
  rt.new_rule([rel.id()], fn() {
    // Attempt to observe a reactive during fixpoint
    ignore(r.observe())
  })
  rt.fixpoint()
}
```

- [ ] **Step 6: Run all tests**

Run: `moon check && moon test -p dowdiness/incr/cells`
Expected: All pass, including panic test (expects abort during fixpoint).

- [ ] **Step 7: Commit**

```bash
git add cells/observer_test.mbt cells/gc_test.mbt
git commit -m "test: add edge case tests for push suspension

GC of suspended reactive, dispose during suspension (idempotent),
source disposal during suspension, pull/hybrid subscriber prevents
suspension, on_observe during fixpoint aborts."
```

---

### Task 5: Scope::add_observer

**Files:**
- Modify: `cells/scope.mbt` (add `add_observer` method)
- Test: `cells/scope_test.mbt`

- [ ] **Step 1: Write failing test**

Add to `cells/scope_test.mbt`:

```moonbit
///|
test "scope: add_observer disposes observer on scope dispose" {
  let rt = Runtime::new()
  let sig = Signal::new(rt, 10)
  let m = Memo::new(rt, fn() { sig.get() * 2 })
  let scope = Scope::new(rt)
  let obs = scope.add_observer(m.observe())
  inspect(obs.get(), content="20")
  inspect(obs.is_disposed(), content="false")
  scope.dispose()
  inspect(obs.is_disposed(), content="true")
}
```

Run: `moon test -p dowdiness/incr/cells -f scope_test.mbt`
Expected: FAIL — `add_observer` does not exist.

- [ ] **Step 2: Implement Scope::add_observer**

In `cells/scope.mbt`, add after the `Scope::add_cell_ids` method (after line 179):

```moonbit
///|
/// Registers an observer with this scope for automatic disposal.
///
/// When the scope is disposed, the observer is disposed in the dispose_hooks
/// phase (step 2 of disposal order — after children, before owned cells).
/// This ensures observers are cleaned up before their potential targets.
///
/// Returns the observer for immediate use.
///
/// # Example
///
/// ```moonbit nocheck
/// let scope = Scope::new(rt)
/// let obs = scope.add_observer(external_memo.observe())
/// inspect(obs.get(), content="value")
/// scope.dispose()  // obs.dispose() called automatically
/// ```
pub fn[T] Scope::add_observer(
  self : Scope,
  obs : Observer[T],
) -> Observer[T] {
  guard !self.disposed else {
    abort("Scope::add_observer called on a disposed scope")
  }
  self.dispose_hooks.push(fn() { obs.dispose() })
  obs
}
```

- [ ] **Step 3: Run test**

Run: `moon check && moon test -p dowdiness/incr/cells -f scope_test.mbt`
Expected: All pass.

- [ ] **Step 4: Write test — observer manually disposed before scope**

Add to `cells/scope_test.mbt`:

```moonbit
///|
test "scope: manual observer dispose before scope dispose is safe" {
  let rt = Runtime::new()
  let sig = Signal::new(rt, 1)
  let m = Memo::new(rt, fn() { sig.get() })
  let scope = Scope::new(rt)
  let obs = scope.add_observer(m.observe())
  // User disposes observer early
  obs.dispose()
  inspect(obs.is_disposed(), content="true")
  // Scope dispose calls obs.dispose() again — idempotent, no abort
  scope.dispose()
}
```

- [ ] **Step 5: Write test — scope disposes observer before owned cells**

Add to `cells/scope_test.mbt`:

```moonbit
///|
test "scope: observer disposed before owned cells" {
  let rt = Runtime::new()
  let scope = Scope::new(rt)
  let sig = scope.signal(10)
  let m = scope.memo(fn() { sig.get() * 2 })
  // Observe the scope's own memo
  let obs = scope.add_observer(m.observe())
  ignore(obs.get())
  // Scope dispose: hooks run (observer disposed) before cells disposed
  // Observer::dispose checks is_cell_disposed — memo is still alive at hook time
  scope.dispose()
  inspect(obs.is_disposed(), content="true")
  assert_true(m.is_disposed())
}
```

- [ ] **Step 6: Write panic test — add_observer on disposed scope**

Add to `cells/scope_test.mbt`:

```moonbit
///|
test "panic scope: add_observer on disposed scope aborts" {
  let rt = Runtime::new()
  let sig = Signal::new(rt, 1)
  let m = Memo::new(rt, fn() { sig.get() })
  let scope = Scope::new(rt)
  scope.dispose()
  ignore(scope.add_observer(m.observe()))
}
```

- [ ] **Step 7: Run all scope tests**

Run: `moon test -p dowdiness/incr/cells -f scope_test.mbt`
Expected: All pass.

- [ ] **Step 8: Commit**

```bash
git add cells/scope.mbt cells/scope_test.mbt
git commit -m "feat: add Scope::add_observer for scoped observer lifecycle

Registers an observer's dispose closure in the scope's dispose_hooks.
Observer is disposed in step 2 of scope disposal (after children,
before owned cells). Idempotent — safe if user disposes manually first."
```

---

### Task 6: MemoMap::sweep

**Files:**
- Modify: `cells/memo_map.mbt` (add `sweep` method)
- Test: `cells/memo_map_test.mbt`

- [ ] **Step 1: Write failing test**

Add to `cells/memo_map_test.mbt`:

```moonbit
///|
test "memo_map: sweep removes disposed entries" {
  let rt = Runtime::new()
  let source = Signal::new(rt, 10)
  let by_key = MemoMap::new(rt, (key : Int) => source.get() + key)
  // Force creation of 3 entries by reading them
  inspect(by_key.get(1), content="11")
  inspect(by_key.get(2), content="12")
  inspect(by_key.get(3), content="13")
  inspect(by_key.length(), content="3")
  // All 3 memos are Interior with no observers, so gc collects all 3.
  rt.gc()
  let swept = by_key.sweep()
  inspect(swept, content="3")
  inspect(by_key.length(), content="0")
}
```

Run: `moon test -p dowdiness/incr/cells -f memo_map_test.mbt`
Expected: FAIL — `sweep` does not exist.

- [ ] **Step 2: Implement MemoMap::sweep**

In `cells/memo_map.mbt`, add after the `get_or_create_memo` method (after line 121):

```moonbit
///|
/// Removes entries whose memos have been disposed (e.g. by gc()).
///
/// Two-pass: collects keys to remove, then removes them (cannot mutate
/// HashMap during iteration). Returns the number of entries swept.
///
/// Call after `Runtime::gc()` to clean up stale entries.
pub fn[K : Hash + Eq, V] MemoMap::sweep(self : MemoMap[K, V]) -> Int {
  let to_remove : Array[K] = []
  for key, memo in self.entries {
    if memo.is_disposed() {
      to_remove.push(key)
    }
  }
  for key in to_remove {
    self.entries.remove(key)
  }
  to_remove.length()
}
```

- [ ] **Step 3: Run tests**

Run: `moon check && moon test -p dowdiness/incr/cells -f memo_map_test.mbt`
Expected: All pass.

- [ ] **Step 4: Write test — sweep on empty map is no-op**

Add to `cells/memo_map_test.mbt`:

```moonbit
///|
test "memo_map: sweep on empty map returns 0" {
  let rt = Runtime::new()
  let by_key = MemoMap::new(rt, (key : Int) => key * 10)
  inspect(by_key.sweep(), content="0")
}
```

- [ ] **Step 5: Write test — sweep with no disposed entries**

Add to `cells/memo_map_test.mbt`:

```moonbit
///|
test "memo_map: sweep with all entries alive returns 0" {
  let rt = Runtime::new()
  let source = Signal::new(rt, 1)
  let by_key = MemoMap::new(rt, (key : Int) => source.get() + key)
  ignore(by_key.get(1))
  ignore(by_key.get(2))
  // No gc, no disposal — all entries alive
  inspect(by_key.sweep(), content="0")
  inspect(by_key.length(), content="2")
}
```

- [ ] **Step 6: Run all memo_map tests**

Run: `moon test -p dowdiness/incr/cells -f memo_map_test.mbt`
Expected: All pass.

- [ ] **Step 7: Commit**

```bash
git add cells/memo_map.mbt cells/memo_map_test.mbt
git commit -m "feat: add MemoMap::sweep for post-gc cleanup

Two-pass removal of entries pointing to disposed memos. Returns
the number of swept entries. Call after Runtime::gc() to clean up
stale HashMap entries."
```

---

### Task 7: Integration tests

**Files:**
- Test: `tests/subscriber_test.mbt` (push suspension integration)
- Test: `tests/integration_test.mbt` (scope + memo_map integration)

- [ ] **Step 1: Write integration test — full suspend/activate lifecycle**

Add to `tests/subscriber_test.mbt`:

```moonbit
///|
test "push suspension: full lifecycle via public API" {
  let rt = @incr.Runtime()
  let sig = @incr.Signal(rt, 10)
  let r = @incr.Reactive::new(rt, fn() { sig.get() * 2 })
  // Observe
  let obs = r.observe()
  inspect(obs.get(), content="20")
  // Change while observed
  sig.set(30)
  inspect(obs.get(), content="60")
  // Unobserve — suspends
  obs.dispose()
  // Change while suspended
  sig.set(100)
  // Re-observe — catches up
  let obs2 = r.observe()
  inspect(obs2.get(), content="200")
  // Change while re-observed
  sig.set(1)
  inspect(obs2.get(), content="2")
  obs2.dispose()
}
```

- [ ] **Step 2: Write integration test — scope add_observer with reactive suspension**

Add to `tests/integration_test.mbt`:

```moonbit
///|
test "scope: add_observer triggers suspension on scope dispose" {
  let rt = @incr.Runtime()
  let sig = @incr.Signal(rt, 5)
  let r = @incr.Reactive::new(rt, fn() { sig.get() + 1 })
  let scope = @incr.Scope::new(rt)
  let obs = scope.add_observer(r.observe())
  inspect(obs.get(), content="6")
  sig.set(10)
  inspect(obs.get(), content="11")
  // Scope dispose triggers observer dispose triggers on_unobserve
  scope.dispose()
  // Reactive is suspended — gc can collect it
  rt.gc()
  assert_true(r.is_disposed())
}
```

- [ ] **Step 3: Write integration test — MemoMap sweep after gc**

Add to `tests/integration_test.mbt`:

```moonbit
///|
test "memo_map: sweep after gc cleans up disposed entries" {
  let rt = @incr.Runtime()
  let source = @incr.Signal(rt, 1)
  let mm = @incr.MemoMap(rt, (k : Int) => source.get() + k)
  // Create entries
  ignore(mm.get(10))
  ignore(mm.get(20))
  inspect(mm.length(), content="2")
  // No observers — gc collects all interior memos
  rt.gc()
  inspect(mm.sweep(), content="2")
  inspect(mm.length(), content="0")
  // Fresh entries can be recreated
  inspect(mm.get(10), content="11")
  inspect(mm.length(), content="1")
}
```

- [ ] **Step 4: Run all tests**

Run: `moon test -p dowdiness/incr/tests`
Expected: All pass.

- [ ] **Step 5: Commit**

```bash
git add tests/subscriber_test.mbt tests/integration_test.mbt
git commit -m "test: add Layer 4b integration tests

Full suspend/activate lifecycle via public API, scope add_observer
triggering suspension on dispose, MemoMap sweep after gc."
```

---

### Task 8: Regenerate interfaces and final verification

**Files:**
- Modify: `cells/cells.mbti` (auto-generated)
- Modify: `incr.mbti` (auto-generated)

- [ ] **Step 1: Regenerate interfaces and format**

Run: `moon info && moon fmt`

- [ ] **Step 2: Check for unintended API changes**

Run: `git diff *.mbti`

Expected new entries:
- `cells.mbti`: `fn Scope::add_observer[T](Scope, Observer[T]) -> Observer[T]`
- `cells.mbti`: `fn MemoMap::sweep[K : Hash + Eq, V](MemoMap[K, V]) -> Int`

Expected change:
- `Runtime::add_gc_root` is `fn` (package-private), so it should NOT appear in `.mbti`

Verify no unintended trait bound changes.

- [ ] **Step 3: Run full test suite**

Run: `moon test`
Expected: All tests pass (cells + tests + pipeline packages).

- [ ] **Step 4: Run benchmarks for regression check**

Run: `moon bench --release`
Expected: No significant regression from baseline.

- [ ] **Step 5: Commit**

```bash
git add -A
git commit -m "chore: regenerate .mbti interfaces for Layer 4b"
```

- [ ] **Step 6: Archive the spec**

The spec stays in `docs/superpowers/specs/` (not archived until all of Layer 4b is merged and the plan is complete).

Update `docs/todo.md` if it tracks Layer 4b as pending work.
