# Per-Cell Callbacks Implementation Plan

> **For Claude:** REQUIRED SUB-SKILL: Use superpowers:executing-plans to implement this plan task-by-task.

**Goal:** Add per-cell `on_change` callbacks to `Signal[T]` and `Memo[T]` that fire before the global `Runtime::fire_on_change()`.

**Architecture:** Add `mut on_change : (() -> Unit)?` to `CellMeta` (type-erased). The typed public APIs on `Signal` and `Memo` capture the value in a closure before storing. Signal callbacks fire in `set_unconditional` and `commit_batch`. Memo callbacks fire lazily in `recompute_inner` only when the value actually changes.

**Tech Stack:** MoonBit — same patterns as existing `recompute_and_check` and `commit_pending` closures in `CellMeta`.

---

### Task 1: Write all failing tests

**Files:**
- Create: `callback_test.mbt`

**Step 1: Create the test file**

```moonbit
///|
test "Signal callback fires on value change" {
  let rt = Runtime::new()
  let s = Signal::new(rt, 0)
  let called : Ref[Bool] = { val: false }
  let received : Ref[Int] = { val: 0 }
  s.on_change(v => {
    called.val = true
    received.val = v
  })
  s.set(42)
  inspect(called.val, content="true")
  inspect(received.val, content="42")
}

///|
test "Signal callback does not fire on same value" {
  let rt = Runtime::new()
  let s = Signal::new(rt, 5)
  let count : Ref[Int] = { val: 0 }
  s.on_change(_v => count.val = count.val + 1)
  s.set(5)
  inspect(count.val, content="0")
}

///|
test "Memo callback fires on get() when value changed" {
  let rt = Runtime::new()
  let s = Signal::new(rt, 1)
  let m = Memo::new(rt, () => s.get() * 10)
  let _ = m.get()
  let received : Ref[Int] = { val: 0 }
  m.on_change(v => received.val = v)
  s.set(2)
  let _ = m.get()
  inspect(received.val, content="20")
}

///|
test "Memo callback does not fire when value backdated" {
  let rt = Runtime::new()
  let s = Signal::new(rt, 2)
  // This memo always computes to 1 regardless of input
  let m = Memo::new(rt, () => s.get() * 0 + 1)
  let _ = m.get()
  let count : Ref[Int] = { val: 0 }
  m.on_change(_v => count.val = count.val + 1)
  s.set(4)
  let _ = m.get()
  inspect(count.val, content="0")
}

///|
test "per-cell callback fires before global on_change" {
  let rt = Runtime::new()
  let s = Signal::new(rt, 0)
  let order : Ref[String] = { val: "" }
  s.on_change(_v => order.val = order.val + "cell ")
  rt.set_on_change(() => order.val = order.val + "global")
  s.set(1)
  inspect(order.val, content="cell global")
}

///|
test "clear_on_change removes Signal callback" {
  let rt = Runtime::new()
  let s = Signal::new(rt, 0)
  let count : Ref[Int] = { val: 0 }
  s.on_change(_v => count.val = count.val + 1)
  s.set(1)
  s.clear_on_change()
  s.set(2)
  inspect(count.val, content="1")
}

///|
test "batch: per-cell callbacks fire once per changed signal" {
  let rt = Runtime::new()
  let s1 = Signal::new(rt, 0)
  let s2 = Signal::new(rt, 0)
  let count1 : Ref[Int] = { val: 0 }
  let count2 : Ref[Int] = { val: 0 }
  s1.on_change(_v => count1.val = count1.val + 1)
  s2.on_change(_v => count2.val = count2.val + 1)
  rt.batch(() => {
    s1.set(1)
    s2.set(1)
  })
  inspect(count1.val, content="1")
  inspect(count2.val, content="1")
}
```

**Step 2: Run to verify it fails**

```bash
moon test -p dowdiness/incr -f callback_test.mbt 2>&1 | head -20
```

Expected: compile error — `Signal` has no method `on_change`.

---

### Task 2: Add `on_change` field to `CellMeta`

**Files:**
- Modify: `cell.mbt:46-119`

**Step 1: Add the field to the struct**

In `cell.mbt`, find the `CellMeta` struct (starts around line 46). Add the new field after `commit_pending`:

```moonbit
priv struct CellMeta {
  id : CellId
  kind : CellKind
  mut changed_at : Revision
  mut verified_at : Revision
  mut dependencies : Array[CellId]
  mut durability : Durability
  recompute_and_check : (() -> Result[Bool, CycleError])?
  mut commit_pending : (() -> Bool)?
  mut on_change : (() -> Unit)?   // NEW
  mut in_progress : Bool
}
```

**Step 2: Initialize in `CellMeta::new_input`**

Find `CellMeta::new_input` (around line 76). Add `on_change: None` before `in_progress`:

```moonbit
fn CellMeta::new_input(id : CellId, durability : Durability) -> CellMeta {
  {
    id,
    kind: Input,
    changed_at: Revision::initial(),
    verified_at: Revision::initial(),
    dependencies: [],
    durability,
    recompute_and_check: None,
    commit_pending: None,
    on_change: None,         // NEW
    in_progress: false,
  }
}
```

**Step 3: Initialize in `CellMeta::new_derived`**

Find `CellMeta::new_derived` (around line 104). Add `on_change: None` before `in_progress`:

```moonbit
fn CellMeta::new_derived(
  id : CellId,
  recompute_and_check : () -> Result[Bool, CycleError],
) -> CellMeta {
  {
    id,
    kind: Derived,
    changed_at: Revision::initial(),
    verified_at: Revision::initial(),
    dependencies: [],
    durability: Low,
    recompute_and_check: Some(recompute_and_check),
    commit_pending: None,
    on_change: None,         // NEW
    in_progress: false,
  }
}
```

**Step 4: Type-check**

```bash
moon check 2>&1
```

Expected: compiles (tests still fail because Signal/Memo methods don't exist yet).

---

### Task 3: Add Signal callbacks + fire in `set_unconditional`

**Files:**
- Modify: `signal.mbt`

**Step 1: Write failing test first** (already done in Task 1)

**Step 2: Add `Signal::on_change`**

Append to the end of `signal.mbt`:

```moonbit
///|
/// Registers a callback that fires whenever this signal's value changes.
///
/// The callback receives the new value. It fires after the value is updated
/// but before `Runtime::fire_on_change()`. Only one callback can be
/// registered at a time; calling this again replaces the previous callback.
///
/// # Parameters
///
/// - `f`: Called with the new value whenever this signal changes
pub fn[T] Signal::on_change(self : Signal[T], f : (T) -> Unit) -> Unit {
  let cell = self.rt.get_cell(self.cell_id)
  cell.on_change = Some(() => f(self.value))
}

///|
/// Removes the `on_change` callback for this signal.
pub fn[T] Signal::clear_on_change(self : Signal[T]) -> Unit {
  let cell = self.rt.get_cell(self.cell_id)
  cell.on_change = None
}
```

**Step 3: Fire in `set_unconditional`**

Find `Signal::set_unconditional` (around line 186). Add the per-cell callback fire between updating `verified_at` and calling `fire_on_change`:

```moonbit
pub fn[T] Signal::set_unconditional(self : Signal[T], new_value : T) -> Unit {
  if self.rt.batch_depth > 0 {
    self.set_batch_unconditional(new_value)
  } else {
    self.value = new_value
    self.rt.bump_revision(self.durability)
    let meta = self.rt.get_cell(self.cell_id)
    meta.changed_at = self.rt.current_revision
    meta.verified_at = self.rt.current_revision
    match meta.on_change {           // NEW
      Some(f) => f()                 // NEW
      None => ()                     // NEW
    }                                // NEW
    self.rt.fire_on_change()
  }
}
```

**Step 4: Run Signal tests**

```bash
moon test -p dowdiness/incr -f callback_test.mbt 2>&1
```

Expected: tests 1, 2, 5, 6 pass. Tests 3, 4 fail (Memo not implemented). Test 7 fails (batch not implemented).

**Step 5: Run full suite — no regressions**

```bash
moon test 2>&1 | tail -3
```

Expected: existing tests still pass (new tests may fail — that's OK).

**Step 6: Commit**

```bash
git add cell.mbt signal.mbt callback_test.mbt
git commit -m "feat: add Signal::on_change and clear_on_change"
```

---

### Task 4: Fire per-cell callbacks in `commit_batch`

**Files:**
- Modify: `runtime.mbt:349-364`

**Step 1: Find the batch commit loop**

In `runtime.mbt`, find `Runtime::commit_batch`. Inside the `if changed_ids.length() > 0` block, locate the sweep loop that sets `changed_at`/`verified_at` (around line 357):

```moonbit
let rev = self.current_revision
for i = 0; i < changed_ids.length(); i = i + 1 {
  let meta = self.get_cell(changed_ids[i])
  meta.changed_at = rev
  meta.verified_at = rev
}
```

**Step 2: Add per-cell callback firing after the sweep, before `fire_on_change`**

```moonbit
let rev = self.current_revision
for i = 0; i < changed_ids.length(); i = i + 1 {
  let meta = self.get_cell(changed_ids[i])
  meta.changed_at = rev
  meta.verified_at = rev
}
// Fire per-cell callbacks before global on_change          // NEW
for i = 0; i < changed_ids.length(); i = i + 1 {          // NEW
  let meta = self.get_cell(changed_ids[i])                  // NEW
  match meta.on_change {                                     // NEW
    Some(f) => f()                                          // NEW
    None => ()                                              // NEW
  }                                                         // NEW
}                                                           // NEW
self.batch_max_durability = Low
self.fire_on_change()
```

**Step 3: Run batch test**

```bash
moon test -p dowdiness/incr -f callback_test.mbt -i 6 2>&1
```

Expected: test 7 ("batch: per-cell callbacks fire once per changed signal") passes.

**Step 4: Run full suite**

```bash
moon test 2>&1 | tail -3
```

Expected: no regressions.

**Step 5: Commit**

```bash
git add runtime.mbt
git commit -m "feat: fire per-cell callbacks in batch commit"
```

---

### Task 5: Add Memo callbacks + fire in `recompute_inner`

**Files:**
- Modify: `memo.mbt`

**Step 1: Add `Memo::on_change` and `Memo::clear_on_change`**

Append to the end of `memo.mbt`:

```moonbit
///|
/// Registers a callback that fires whenever this memo's value changes.
///
/// The callback fires lazily — only during `get()` when recomputation
/// produces a new value. It does not fire if the memo backdates (recomputes
/// to the same value). Only one callback can be registered at a time.
///
/// # Parameters
///
/// - `f`: Called with the new value whenever this memo's value changes
pub fn[T] Memo::on_change(self : Memo[T], f : (T) -> Unit) -> Unit {
  let cell = self.rt.get_cell(self.cell_id)
  cell.on_change = Some(() => {
    match self.value {
      Some(v) => f(v)
      None => ()
    }
  })
}

///|
/// Removes the `on_change` callback for this memo.
pub fn[T] Memo::clear_on_change(self : Memo[T]) -> Unit {
  let cell = self.rt.get_cell(self.cell_id)
  cell.on_change = None
}
```

**Step 2: Fire in `recompute_inner`**

Find `Memo::recompute_inner` (around line 215). It currently reads:

```moonbit
fn[T : Eq] Memo::recompute_inner(self : Memo[T]) -> Result[Bool, CycleError] {
  let cell = self.rt.get_cell(self.cell_id)
  let old_changed_at = cell.changed_at
  match self.force_recompute() {
    Ok(_) => Ok(cell.changed_at != old_changed_at)
    Err(e) => Err(e)
  }
}
```

Replace with:

```moonbit
fn[T : Eq] Memo::recompute_inner(self : Memo[T]) -> Result[Bool, CycleError] {
  let cell = self.rt.get_cell(self.cell_id)
  let old_changed_at = cell.changed_at
  match self.force_recompute() {
    Ok(_) => {
      let changed = cell.changed_at != old_changed_at
      if changed {                          // NEW
        match cell.on_change {             // NEW
          Some(f) => f()                   // NEW
          None => ()                       // NEW
        }                                  // NEW
      }                                    // NEW
      Ok(changed)
    }
    Err(e) => Err(e)
  }
}
```

**Step 3: Run all callback tests**

```bash
moon test -p dowdiness/incr -f callback_test.mbt 2>&1
```

Expected: all 9 tests pass.

**Step 4: Run full suite**

```bash
moon test 2>&1 | tail -3
```

Expected: all 114 + 9 = 123 tests pass, zero failures.

**Step 5: Commit**

```bash
git add memo.mbt callback_test.mbt
git commit -m "feat: add Memo::on_change and clear_on_change"
```

---

### Task 6: Update todo.md

**Files:**
- Modify: `docs/todo.md`

**Step 1: Mark Phase 2B items as done**

Find the Per-Cell Callbacks section and change all `[ ]` to `[x]`:

```markdown
### Per-Cell Callbacks (Phase 2B - High Priority)

- [x] Add `on_change : (() -> Unit)?` field to `CellMeta` (or type-erased callback)
- [x] Add `Signal::on_change(self, f : (T) -> Unit) -> Unit`
- [x] Add `Memo::on_change(self, f : (T) -> Unit) -> Unit`
- [x] Add `Signal::clear_on_change(self) -> Unit`
- [x] Add `Memo::clear_on_change(self) -> Unit`
- [x] Fire per-cell callbacks before `Runtime::fire_on_change()`
- [x] Test callback execution order (per-cell before global)
```

**Step 2: Commit**

```bash
git add docs/todo.md
git commit -m "docs: mark Phase 2B per-cell callbacks as done"
```
