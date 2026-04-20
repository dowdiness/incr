# Layer 5: API Boundary Enforcement — Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Restrict `.get()` on interior cells (Memo, HybridMemo, Reactive) to tracked context only, add `Signal::peek()`, and migrate all tests to use `rt.read()`/observers for outside-the-graph reads.

**Architecture:** Interior cell `.get()` methods gain a guard that aborts when `tracking_stack` is empty. A new internal `get_untracked()` method bypasses this guard for Observer and rt.read(). `Signal::peek()` is added for API completeness (alias for `.get()` since signals never need tracking). Tests migrate from `memo.get()` to `rt.read(memo)` for top-level reads.

**Tech Stack:** MoonBit, moon test, moon check

---

## Scope

This plan covers the `incr` module only. Downstream consumers (loom parser's `ReactiveParser::cst()`, `::term()`, `::get_source()`) call `.get()` on Memo from public methods outside tracked context — those are out of scope for this PR and will need separate migration in the loom module (likely switching to observer-backed getters or `rt.read()`).

**Note on `Signal.get()`:** The spec says `signal.get()` inside compute creates tracked dependency, and `signal.peek()` reads from outside without tracking. However, `Signal.get()` already works outside tracked context (it's a no-op when tracking_stack is empty). Per the spec's API contract, signals are Source cells — readable from anywhere. We add `peek()` as an explicit untracked-read API for clarity, but do NOT restrict `Signal.get()`. The restriction applies only to Interior cells: Memo, HybridMemo, Reactive.

## File Structure

**Modified files:**

| File | Change |
|------|--------|
| `cells/signal.mbt` | Add `Signal::peek()` method |
| `cells/tracked_cell.mbt` | Add `TrackedCell::peek()` delegating to Signal::peek() |
| `cells/memo.mbt` | Add tracked-context guard to `get_result()`; add `Memo::get_untracked()` (priv) |
| `cells/hybrid_memo.mbt` | Add tracked-context guard to `get()`; add `HybridMemo::get_untracked()` (priv) |
| `cells/push_reactive.mbt` | Add tracked-context guard to `get()`; add `Reactive::get_untracked()` (priv) |
| `cells/observer.mbt` | Switch Observer getter closures from `.get()` to `.get_untracked()` |
| `cells/memo_test.mbt` | Migrate top-level `.get()` → `rt.read()` |
| `cells/callback_test.mbt` | Migrate top-level `.get()` → `rt.read()` |
| `cells/on_change_test.mbt` | Migrate top-level `.get()` → `rt.read()` |
| `cells/custom_eq_test.mbt` | Migrate top-level `.get()` → `rt.read()` |
| `cells/introspection_test.mbt` | Migrate top-level `.get()` → `rt.read()` |
| `cells/cycle_test.mbt` | Migrate top-level `.get()` → `rt.read()` |
| `cells/cycle_path_test.mbt` | Migrate top-level `.get()` → `rt.read()` |
| `cells/dispose_test.mbt` | Migrate top-level `.get()` → `rt.read()` |
| `cells/backdating_test.mbt` | Migrate top-level `.get()` → `rt.read()` |
| `cells/verify_path_test.mbt` | Migrate top-level `.get()` → `rt.read()` |
| `cells/debug_test.mbt` | Migrate top-level `.get()` → `rt.read()` |
| `cells/observer_test.mbt` | Migrate remaining top-level `.get()` → `rt.read()` |
| `cells/gc_test.mbt` | Migrate top-level `.get()` → `rt.read()` |
| `cells/memo_map_test.mbt` | Migrate top-level `.get()` → `rt.read()` |
| `cells/scope_test.mbt` | Migrate top-level `.get()` → `rt.read()` |
| `cells/hybrid_wbtest.mbt` | Migrate top-level `.get()` → `rt.read_hybrid()` |
| `cells/push_reactive_wbtest.mbt` | Migrate top-level `.get()` → `rt.read_reactive()` |
| `cells/batch_wbtest.mbt` | Migrate top-level `.get()` → `rt.read()` |
| `cells/durability_wbtest.mbt` | Migrate top-level `.get()` → `rt.read()` |
| `cells/tracking_wbtest.mbt` | Migrate if needed |
| `cells/subscriber_wbtest.mbt` | Migrate if needed |
| `cells/subscriber_link_wbtest.mbt` | Migrate if needed |
| `cells/memo_dep_diff_wbtest.mbt` | Migrate if needed |
| `cells/cell_ops_wbtest.mbt` | Migrate if needed |
| `cells/verify_wbtest.mbt` | Migrate if needed |
| `cells/pull_verify_wbtest.mbt` | Migrate if needed |
| `cells/cell_wbtest.mbt` | Migrate if needed |
| `cells/soa_wbtest.mbt` | Migrate if needed |
| `cells/runtime_wbtest.mbt` | Migrate if needed |
| `cells/dispose_wbtest.mbt` | Migrate if needed |
| `cells/gc_wbtest.mbt` | Migrate if needed |
| `cells/cell_ref_wbtest.mbt` | Migrate if needed |
| `cells/push_reachable_wbtest.mbt` | Migrate if needed |
| `cells/push_efficiency_bench_test.mbt` | Migrate if needed |
| `cells/signal_wbtest.mbt` | No change (Signal.get() stays unrestricted) |
| `cells/committable_wbtest.mbt` | Migrate if needed |
| `cells/datalog_test.mbt` | Migrate if needed |
| `cells/datalog_wbtest.mbt` | Migrate if needed |
| `cells/datalog_functional_relation_wbtest.mbt` | Migrate if needed |
| `tests/integration_test.mbt` | Migrate top-level `.get()` → `rt.read()` |
| `tests/hybrid_test.mbt` | Migrate top-level `.get()` → `rt.read_hybrid()` |
| `tests/traits_test.mbt` | Migrate top-level `.get()` → `rt.read()` |
| `tests/tracked_struct_test.mbt` | Migrate top-level `.get()` → `rt.read()` |
| `tests/fanout_test.mbt` | Migrate top-level `.get()` → `rt.read()` |
| `tests/subscriber_test.mbt` | Migrate top-level `.get()` → `rt.read()` |
| `tests/bench_test.mbt` | Migrate if needed (check if calls are inside closures) |
| `tests/backdate_eq_test.mbt` | Migrate if needed |

---

## Task 1: Add Signal::peek() and TrackedCell::peek()

**Files:**
- Modify: `cells/signal.mbt` (after `Signal::get`, ~line 93)
- Modify: `cells/tracked_cell.mbt` (after `TrackedCell::get`, ~line 71)

- [ ] **Step 1.1: Add Signal::peek() method**

In `cells/signal.mbt`, add after the `Signal::get` method (after line 93):

```moonbit
///|
/// Returns the current value of the signal without recording a dependency.
///
/// Use `peek()` to read a signal's value from outside the dependency graph
/// (e.g., in event handlers, logging, or tests). Unlike `get()`, this never
/// records a dependency even when called inside a compute function.
///
/// # Returns
///
/// The current value of the signal
pub fn[T] Signal::peek(self : Signal[T]) -> T {
  guard !self.rt.is_cell_disposed(self.cell_id) else {
    abort("Signal::peek called on a disposed signal")
  }
  self.value
}
```

- [ ] **Step 1.2: Add TrackedCell::peek() method**

In `cells/tracked_cell.mbt`, add after `TrackedCell::get` (after line 71):

```moonbit
///|
/// Returns the current value of the cell without recording a dependency.
///
/// Delegates to `Signal::peek()` on the inner signal. Use from outside
/// the dependency graph when you don't want to trigger recomputation.
pub fn[T] TrackedCell::peek(self : TrackedCell[T]) -> T {
  self.signal.peek()
}
```

- [ ] **Step 1.3: Run moon check**

Run: `moon check`
Expected: 0 errors

- [ ] **Step 1.4: Run all tests to verify no regressions**

Run: `moon test`
Expected: All tests pass (no behavior change — just new methods)

- [ ] **Step 1.5: Commit**

```bash
git add cells/signal.mbt cells/tracked_cell.mbt
git commit -m "feat: add Signal::peek() and TrackedCell::peek() for untracked reads"
```

---

## Task 2: Add internal get_untracked() methods and tracked-context guards

This task adds the tracked-context guard to Memo, HybridMemo, and Reactive `.get()` methods, and provides internal `get_untracked()` methods for Observer/rt.read() to bypass the guard.

**Key design decision:** The guard checks `self.rt.core.tracking_stack.length() == 0`. When the tracking stack is empty, we are outside any compute function — the `.get()` call cannot record a dependency and should not be allowed for interior cells. The error message directs users to `rt.read()` or `observe()`.

**Files:**
- Modify: `cells/memo.mbt`
- Modify: `cells/hybrid_memo.mbt`
- Modify: `cells/push_reactive.mbt`
- Modify: `cells/observer.mbt`

- [ ] **Step 2.1: Add Memo::get_untracked() and guard to Memo::get_result()**

In `cells/memo.mbt`, add the `get_untracked` method after `Memo::get_or_else` (after line 278):

```moonbit
///|
/// Internal: returns the memoized value without requiring tracked context.
///
/// Used by Observer and rt.read() to read interior cells from outside the
/// dependency graph. Bypasses the tracked-context guard but otherwise
/// follows the same verification path as get_result().
fn[T] Memo::get_untracked(self : Memo[T]) -> T {
  match self.get_result_inner() {
    Ok(value) => value
    Err(e) => abort(e.format_path(self.rt))
  }
}
```

Then refactor `Memo::get_result()` to delegate to a shared `get_result_inner()` method. Replace the body of `Memo::get_result()` (lines 194-255) with:

```moonbit
pub fn[T] Memo::get_result(self : Memo[T]) -> Result[T, CycleError] {
  guard !self.rt.is_cell_disposed(self.cell_id) else {
    abort("Memo::get called on a disposed memo")
  }
  let active_rt = current_computing_runtime_id.val
  if active_rt >= 0 && active_rt != self.rt.core.runtime_id {
    current_computing_runtime_id.val = -1
    abort(
      "Cross-runtime dependency: Memo belongs to Runtime " +
      self.rt.core.runtime_id.to_string() +
      " but is read inside a memo on Runtime " +
      active_rt.to_string(),
    )
  }
  guard self.rt.core.tracking_stack.length() > 0 else {
    abort(
      "Memo::get() called outside tracked context. Use rt.read(memo) or memo.observe() to read from outside the graph.",
    )
  }
  if self.rt.core.in_fixpoint {
    abort(
      "Memo::get() cannot be called during fixpoint(); read relations directly or call get() after fixpoint() completes",
    )
  }
  self.get_result_inner()
}
```

Add the shared inner method (private):

```moonbit
///|
/// Shared verification logic for get_result() and get_untracked().
/// Does NOT check tracked context — callers are responsible for the guard.
fn[T] Memo::get_result_inner(self : Memo[T]) -> Result[T, CycleError] {
  guard !self.rt.is_cell_disposed(self.cell_id) else {
    abort("Memo::get called on a disposed memo")
  }
  match self.value {
    None =>
      match self.force_recompute() {
        Ok(value) => {
          self.rt.record_dependency(self.cell_id)
          Ok(value)
        }
        Err(e) => Err(e)
      }
    Some(cached) => {
      let cell = self.rt.get_memo_data(self.cell_id)
      if cell.verified_at >= self.rt.core.current_revision {
        self.rt.record_dependency(self.cell_id)
        return Ok(cached)
      }
      match self.rt.pull_verify(self.cell_id) {
        Ok(_) => {
          self.rt.record_dependency(self.cell_id)
          match self.value {
            Some(v) => Ok(v)
            None =>
              abort(
                "unreachable: value is always Some after successful verification",
              )
          }
        }
        Err(e) => Err(e)
      }
    }
  }
}
```

- [ ] **Step 2.2: Add HybridMemo::get_untracked() and guard to HybridMemo::get()**

In `cells/hybrid_memo.mbt`, add `get_untracked` after `HybridMemo::get` (after line 131):

```moonbit
///|
/// Internal: returns the memoized value without requiring tracked context.
///
/// Used by Observer and rt.read_hybrid() to read hybrid memos from outside
/// the dependency graph.
fn[T : Eq] HybridMemo::get_untracked(self : HybridMemo[T]) -> T {
  guard !self.rt.is_cell_disposed(self.cell_id) else {
    abort("HybridMemo::get called on a disposed hybrid memo")
  }
  if self.rt.core.in_fixpoint {
    abort(
      "HybridMemo::get() cannot be called during fixpoint(); read relations directly or call get() after fixpoint() completes",
    )
  }
  match self.value {
    None =>
      match self.force_recompute() {
        Ok(value) => {
          self.rt.record_dependency(self.cell_id)
          value
        }
        Err(e) => abort(e.format_path(self.rt))
      }
    Some(cached) => {
      let cell = self.rt.get_memo_data(self.cell_id)
      if cell.verified_at >= self.rt.core.current_revision {
        self.rt.record_dependency(self.cell_id)
        return cached
      }
      match self.rt.pull_verify(self.cell_id) {
        Ok(_) => {
          self.rt.record_dependency(self.cell_id)
          match self.value {
            Some(v) => v
            None =>
              abort(
                "unreachable: value is always Some after successful verification",
              )
          }
        }
        Err(e) => abort(e.format_path(self.rt))
      }
    }
  }
}
```

Add the tracked-context guard to `HybridMemo::get()`. Insert after the cross-runtime check (after line 93, before the fixpoint check):

```moonbit
  guard self.rt.core.tracking_stack.length() > 0 else {
    abort(
      "HybridMemo::get() called outside tracked context. Use rt.read_hybrid(memo) or memo.observe() to read from outside the graph.",
    )
  }
```

- [ ] **Step 2.3: Add Reactive::get_untracked() and guard to Reactive::get()**

In `cells/push_reactive.mbt`, add `get_untracked` after `Reactive::get` (after line 224):

```moonbit
///|
/// Internal: returns the cached value without requiring tracked context.
///
/// Used by Observer and rt.read_reactive() to read reactives from outside
/// the dependency graph.
fn[T] Reactive::get_untracked(self : Reactive[T]) -> T {
  let cell_id = self.cell_id.id
  guard !self.rt.is_cell_disposed(cell_id) else {
    abort("Reactive::get called on a disposed reactive")
  }
  self.rt.record_dependency(cell_id)
  self.value.val.unwrap()
}
```

Add the tracked-context guard to `Reactive::get()`. Insert after the cross-runtime check (after line 217, before the disposed guard):

```moonbit
  guard self.rt.core.tracking_stack.length() > 0 else {
    abort(
      "Reactive::get() called outside tracked context. Use rt.read_reactive(reactive) or reactive.observe() to read from outside the graph.",
    )
  }
```

- [ ] **Step 2.4: Switch Observer getter closures to use get_untracked()**

In `cells/observer.mbt`, change the three `.observe()` methods:

In `Memo::observe` (line 72), change:
```moonbit
    getter: fn() { self.get() },
```
to:
```moonbit
    getter: fn() { self.get_untracked() },
```

In `HybridMemo::observe` (line 91), change:
```moonbit
    getter: fn() { self.get() },
```
to:
```moonbit
    getter: fn() { self.get_untracked() },
```

In `Reactive::observe` (line 111), change:
```moonbit
    getter: fn() { self.get() },
```
to:
```moonbit
    getter: fn() { self.get_untracked() },
```

- [ ] **Step 2.5: Run moon check**

Run: `moon check`
Expected: 0 errors (the `get_untracked` methods are `fn` not `pub fn`, visible within the `cells` package)

- [ ] **Step 2.6: Commit**

```bash
git add cells/memo.mbt cells/hybrid_memo.mbt cells/push_reactive.mbt cells/observer.mbt
git commit -m "feat: restrict .get() to tracked context, add get_untracked() for Observer"
```

**Note:** Tests will fail after this commit because they call `.get()` outside tracked context. That's expected — the migration in Tasks 3-7 will fix them.

---

## Task 3: Migrate cells/ blackbox tests (part 1)

Migrate `cells/*_test.mbt` files. These are blackbox tests that import the public API.

**Migration rule:** Replace every `memo.get()` / `hybrid.get()` / `reactive.get()` call that is at test-function scope (NOT inside a `fn()` compute closure) with the appropriate `rt.read*()` call:

- `memo.get()` → `rt.read(memo)`
- `hybrid.get()` → `rt.read_hybrid(hybrid)`
- `reactive.get()` → `rt.read_reactive(reactive)`

**Do NOT change:**
- `.get()` inside `fn() { ... }` compute closures (these are tracked context)
- `Signal::get()` / `TrackedCell::get()` calls (signals are unrestricted)
- `Observer::get()` calls (Observer already uses get_untracked internally)
- `.get()` in panic tests that test the untracked-context abort itself

**Files:**
- Modify: `cells/memo_test.mbt`
- Modify: `cells/callback_test.mbt`
- Modify: `cells/on_change_test.mbt`
- Modify: `cells/custom_eq_test.mbt`
- Modify: `cells/introspection_test.mbt`
- Modify: `cells/dispose_test.mbt`
- Modify: `cells/backdating_test.mbt`
- Modify: `cells/verify_path_test.mbt`
- Modify: `cells/cycle_test.mbt`
- Modify: `cells/cycle_path_test.mbt`
- Modify: `cells/debug_test.mbt`
- Modify: `cells/observer_test.mbt`
- Modify: `cells/gc_test.mbt`
- Modify: `cells/memo_map_test.mbt`
- Modify: `cells/scope_test.mbt`
- Modify: `cells/datalog_test.mbt`

- [ ] **Step 3.1: Read and migrate each test file**

For each file, read it, identify all top-level `.get()` calls on Memo/HybridMemo/Reactive, and replace with `rt.read()` / `rt.read_hybrid()` / `rt.read_reactive()`.

Example migration in `cells/memo_test.mbt`:
```moonbit
// Before:
inspect(doubled.get(), content="20")

// After:
inspect(rt.read(doubled), content="20")
```

Example for `ignore(memo.get())` pattern (priming a memo):
```moonbit
// Before:
ignore(m.get())

// After:
ignore(rt.read(m))
```

**Important patterns to watch for:**

1. **Callback closures:** `.get()` inside `on_change` callbacks runs during `Signal::set_unconditional`, which is NOT inside a tracked context. These need migration too:
```moonbit
// Before (in on_change callback):
s.on_change(fn(_v) { seen.val = m.get() })

// After:
s.on_change(fn(_v) { seen.val = rt.read(m) })
```

2. **Cycle tests:** Tests that specifically test cycle detection via `.get()` calling patterns — these `.get()` calls are inside compute closures and should NOT be changed.

3. **Disposal panic tests:** Tests like `test "panic Memo::get after dispose"` that call `.get()` on disposed cells. These tests verify the dispose guard fires. After our change, the tracked-context guard fires FIRST (since the call is at top level). We need to decide: either change the test to call from tracked context, or accept that the panic message changes. **Decision:** Change these tests to use `rt.read()` instead, which will hit the dispose guard inside `get_untracked()`.

- [ ] **Step 3.2: Run moon check after each file**

Run: `moon check` after each file edit

- [ ] **Step 3.3: Run tests for cells/ package**

Run: `moon test -p dowdiness/incr/cells`
Expected: All tests pass

- [ ] **Step 3.4: Commit**

```bash
git add cells/*_test.mbt
git commit -m "refactor: migrate cells/ blackbox tests from .get() to rt.read()"
```

---

## Task 4: Migrate cells/ whitebox tests

Migrate `cells/*_wbtest.mbt` files. These are whitebox tests with access to private fields.

**Files:**
- Modify: `cells/hybrid_wbtest.mbt`
- Modify: `cells/push_reactive_wbtest.mbt`
- Modify: `cells/batch_wbtest.mbt`
- Modify: `cells/durability_wbtest.mbt`
- Modify: `cells/tracking_wbtest.mbt`
- Modify: `cells/subscriber_wbtest.mbt`
- Modify: `cells/subscriber_link_wbtest.mbt`
- Modify: `cells/memo_dep_diff_wbtest.mbt`
- Modify: `cells/cell_ops_wbtest.mbt`
- Modify: `cells/verify_wbtest.mbt`
- Modify: `cells/pull_verify_wbtest.mbt`
- Modify: `cells/cell_wbtest.mbt`
- Modify: `cells/soa_wbtest.mbt`
- Modify: `cells/runtime_wbtest.mbt`
- Modify: `cells/dispose_wbtest.mbt`
- Modify: `cells/gc_wbtest.mbt`
- Modify: `cells/cell_ref_wbtest.mbt`
- Modify: `cells/push_reachable_wbtest.mbt`
- Modify: `cells/committable_wbtest.mbt`
- Modify: `cells/datalog_wbtest.mbt`
- Modify: `cells/datalog_functional_relation_wbtest.mbt`
- Modify: `cells/signal_wbtest.mbt` (only if it has Memo/Reactive .get() calls)

- [ ] **Step 4.1: Read and migrate each whitebox test file**

Same migration rule as Task 3. Whitebox tests are in the same package so they CAN use the private `get_untracked()` directly if needed, but prefer `rt.read()` for consistency with the public API.

**Special case for whitebox tests:** Some tests directly test internal verification behavior and may need `get_untracked()` instead of `rt.read()` to avoid the observe/dispose overhead of rt.read(). Use judgment: if the test is testing verification mechanics and the observer overhead would interfere, use `get_untracked()`. Otherwise use `rt.read()`.

- [ ] **Step 4.2: Run moon check after each file**

Run: `moon check` after each file edit

- [ ] **Step 4.3: Run tests for cells/ package**

Run: `moon test -p dowdiness/incr/cells`
Expected: All tests pass

- [ ] **Step 4.4: Commit**

```bash
git add cells/*_wbtest.mbt
git commit -m "refactor: migrate cells/ whitebox tests from .get() to rt.read()/get_untracked()"
```

---

## Task 5: Migrate integration tests

Migrate `tests/*.mbt` files.

**Files:**
- Modify: `tests/integration_test.mbt`
- Modify: `tests/hybrid_test.mbt`
- Modify: `tests/traits_test.mbt`
- Modify: `tests/tracked_struct_test.mbt`
- Modify: `tests/fanout_test.mbt`
- Modify: `tests/subscriber_test.mbt`
- Modify: `tests/bench_test.mbt`
- Modify: `tests/backdate_eq_test.mbt`

- [ ] **Step 5.1: Read and migrate each integration test file**

Same migration rule. Integration tests use the public `@incr` API.

**Note on bench_test.mbt:** Benchmark closures like `b.bench(fn() { b.keep(m.get()) })` — the `.get()` is inside `fn()` but this is NOT a compute closure. It's a benchmark iteration closure. These need migration to `rt.read()`.

- [ ] **Step 5.2: Run moon check after each file**

Run: `moon check` after each file edit

- [ ] **Step 5.3: Run tests for tests/ package**

Run: `moon test -p dowdiness/incr/tests`
Expected: All tests pass

- [ ] **Step 5.4: Run benchmarks to verify they still work**

Run: `moon bench --release`
Expected: Benchmarks run without abort

- [ ] **Step 5.5: Commit**

```bash
git add tests/*.mbt
git commit -m "refactor: migrate integration tests from .get() to rt.read()"
```

---

## Task 6: Add panic test for tracked-context guard

**Files:**
- Modify: `cells/memo_test.mbt`

- [ ] **Step 6.1: Add panic test for Memo::get() outside tracked context**

In `cells/memo_test.mbt`, add:

```moonbit
///|
test "panic Memo::get() outside tracked context" {
  let rt = Runtime::new()
  let s = Signal::new(rt, 10)
  let m = Memo::new(rt, fn() { s.get() * 2 })
  ignore(m.get())
}
```

- [ ] **Step 6.2: Add panic test for HybridMemo::get() outside tracked context**

In `cells/memo_test.mbt` (or `cells/observer_test.mbt`), add:

```moonbit
///|
test "panic HybridMemo::get() outside tracked context" {
  let rt = Runtime::new()
  let s = Signal::new(rt, 10)
  let h = HybridMemo::new(rt, fn() { s.get() * 2 })
  ignore(h.get())
}
```

- [ ] **Step 6.3: Add panic test for Reactive::get() outside tracked context**

```moonbit
///|
test "panic Reactive::get() outside tracked context" {
  let rt = Runtime::new()
  let s = Signal::new(rt, 10)
  let r = Reactive::new(rt, fn() { s.get() })
  ignore(r.get())
}
```

- [ ] **Step 6.4: Add positive test — Memo::get() inside tracked context works**

```moonbit
///|
test "Memo::get() inside tracked context succeeds" {
  let rt = Runtime::new()
  let s = Signal::new(rt, 10)
  let m = Memo::new(rt, fn() { s.get() * 2 })
  let m2 = Memo::new(rt, fn() { m.get() + 1 })
  inspect(rt.read(m2), content="21")
}
```

- [ ] **Step 6.5: Add test for Signal::peek()**

```moonbit
///|
test "Signal::peek() reads without tracking" {
  let rt = Runtime::new()
  let s = Signal::new(rt, 42)
  // peek works from outside tracked context
  inspect(s.peek(), content="42")
  // peek does not record dependency
  let m = Memo::new(rt, fn() {
    ignore(s.peek())
    0
  })
  ignore(rt.read(m))
  inspect(m.dependencies().length(), content="0")
}
```

- [ ] **Step 6.6: Run tests**

Run: `moon test -p dowdiness/incr/cells`
Expected: All tests pass (panic tests should trigger the expected abort)

- [ ] **Step 6.7: Commit**

```bash
git add cells/memo_test.mbt
git commit -m "test: add panic tests for tracked-context guard and Signal::peek()"
```

---

## Task 7: Run full test suite and update interfaces

- [ ] **Step 7.1: Run full test suite**

Run: `moon test`
Expected: All tests pass across all packages

- [ ] **Step 7.2: Regenerate .mbti interfaces**

Run: `moon info && moon fmt`

- [ ] **Step 7.3: Check .mbti diff for expected API additions**

Run: `git diff *.mbti`

Expected new entries:
- `Signal::peek[T](Signal[T]) -> T`
- `TrackedCell::peek[T](TrackedCell[T]) -> T`

No other public API changes (get_untracked is private).

- [ ] **Step 7.4: Commit**

```bash
git add -A
git commit -m "chore: regenerate .mbti interfaces for Layer 5"
```

---

## Task 8: Update documentation

**Files:**
- Modify: `docs/plans/2026-04-08-dispose-gc-design.md` (update delivery summary)
- Modify: `docs/roadmap.md` (if it exists — mark Layer 5 complete)
- Modify: `docs/todo.md` (if it tracks Layer 5)

- [ ] **Step 8.1: Update delivery summary in design spec**

Update the Layer 5 entry in the delivery summary to show completion status.

- [ ] **Step 8.2: Update roadmap/todo if applicable**

- [ ] **Step 8.3: Commit**

```bash
git add docs/
git commit -m "docs: update docs for Layer 5 completion"
```

---

## Execution Notes

### Migration Pattern Quick Reference

| Before | After | When |
|--------|-------|------|
| `memo.get()` at test scope | `rt.read(memo)` | Always |
| `h.get()` at test scope | `rt.read_hybrid(h)` | Always |
| `r.get()` at test scope | `rt.read_reactive(r)` | Always |
| `ignore(memo.get())` | `ignore(rt.read(memo))` | Priming pattern |
| `memo.get()` in `fn()` compute | No change | Inside tracked context |
| `signal.get()` anywhere | No change | Signals unrestricted |
| `obs.get()` | No change | Observer uses get_untracked |
| `memo.get()` in on_change callback | `rt.read(memo)` | Callbacks are untracked |

### Parallelization

Tasks 3, 4, and 5 (test migration) are independent and can run in parallel via subagents. Each covers a separate set of files with no overlap. Task 2 must complete first (it adds the guards + get_untracked). Task 6 depends on Task 3 (same file). Task 7 depends on all prior tasks.

### Risk: Downstream breakage

The loom parser (`ReactiveParser::cst()`, `::term()`) calls `Memo::get()` outside tracked context. This is out of scope — the loom module has its own `moon.mod.json` and test suite. After this PR merges, the loom submodule pointer will need updating and its callers will need migration to use `rt.read()` or observer-backed getters. Consider opening a tracking issue.
