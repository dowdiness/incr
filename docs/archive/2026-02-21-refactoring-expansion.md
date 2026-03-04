# Refactoring Expansion Implementation Plan

> **For Claude:** REQUIRED SUB-SKILL: Use superpowers:executing-plans to implement this plan task-by-task.

**Goal:** Apply four new internal quality improvements (items 9–12) identified in the refactoring expansion brainstorm — no new features, no API changes, all tests green throughout.

**Architecture:** Each task is independent. Tasks are ordered lowest-risk first: invariant hardening (11), correctness fix (12), duplication removal (9), then the correctness-critical verification loop refactor (10). TDD throughout: write a targeted test or confirm existing coverage, make the change, verify green.

**Tech Stack:** MoonBit · `moon test` · `moon check`

---

## Task 1: Guard `batch_depth` underflow (Item 11)

**Files:**
- Modify: `runtime.mbt:316–319`
- Test: `batch_wbtest.mbt` (whitebox test, already exists)

### Step 1: Confirm existing batch tests are green

```bash
moon test -p dowdiness/incr -f batch_wbtest.mbt
```

Expected: all pass. This is your baseline.

### Step 2: Add the underflow guard

In `runtime.mbt`, inside `Runtime::batch`, after the decrement on line 316:

**Before:**
```moonbit
pub fn Runtime::batch(self : Runtime, f : () -> Unit) -> Unit {
  self.batch_depth = self.batch_depth + 1
  f()
  self.batch_depth = self.batch_depth - 1
  if self.batch_depth == 0 {
    self.commit_batch()
  }
}
```

**After:**
```moonbit
pub fn Runtime::batch(self : Runtime, f : () -> Unit) -> Unit {
  self.batch_depth = self.batch_depth + 1
  f()
  self.batch_depth = self.batch_depth - 1
  if self.batch_depth < 0 {
    abort("batch_depth underflow: batch() nesting is unbalanced")
  }
  if self.batch_depth == 0 {
    self.commit_batch()
  }
}
```

### Step 3: Run full test suite

```bash
moon test
```

Expected: all 123 tests pass. No existing test hits this abort path.

### Step 4: Commit

```bash
git add runtime.mbt
git commit -m "fix: guard batch_depth underflow in Runtime::batch"
```

---

## Task 2: Fix `CellId::hash` additive combination (Item 12)

**Files:**
- Modify: `cell.mbt:16–18`

### Step 1: Understand the bug

The current `hash` impl uses `+`, which is commutative:
```moonbit
impl Hash for CellId with hash(self) {
  self.runtime_id.hash() + self.id.hash()  // CellId{1,2} == CellId{2,1}
}
```

`CellId{runtime_id: 1, id: 2}` produces the same hash as `CellId{runtime_id: 2, id: 1}`. This causes collisions in `ActiveQuery`'s `HashSet[CellId]` when multiple runtimes exist.

The `hash_combine` impl is already correct — it uses MoonBit's `Hasher` machinery which is order-sensitive.

### Step 2: Verify existing tests are green

```bash
moon test
```

Expected: all pass.

### Step 3: Fix the `hash` impl

Replace the `hash` method in `cell.mbt` with a polynomial combiner (non-commutative):

**Before:**
```moonbit
///|
impl Hash for CellId with hash(self) {
  self.runtime_id.hash() + self.id.hash()
}
```

**After:**
```moonbit
///|
impl Hash for CellId with hash(self) {
  self.runtime_id.hash() * 31 + self.id.hash()
}
```

`* 31` is a standard polynomial hash step — prime multiplier, order-sensitive, no extra imports needed. `CellId{1,2}` → `1*31+2 = 33`; `CellId{2,1}` → `2*31+1 = 63`. No collision.

### Step 4: Run full test suite

```bash
moon test
```

Expected: all pass. HashSet-based deduplication in `ActiveQuery` still works correctly.

### Step 5: Commit

```bash
git add cell.mbt
git commit -m "fix: use non-commutative polynomial hash for CellId"
```

---

## Task 3: Merge identical `Ok` arms in `Memo::get_result` (Item 9)

**Files:**
- Modify: `memo.mbt:141–165`

### Step 1: Read the current code

Open `memo.mbt` and locate `Memo::get_result`. The `Some(_)` branch (line ~141) contains:

```moonbit
Some(_) => {
  if cell.verified_at == self.rt.current_revision {
    self.rt.record_dependency(self.cell_id)
    return Ok(self.value.unwrap())
  }
  match maybe_changed_after(self.rt, self.cell_id, cell.verified_at) {
    Ok(false) => {
      // Green path: nothing changed, verified_at already set by maybe_changed_after
      self.rt.record_dependency(self.cell_id)
      Ok(self.value.unwrap())
    }
    Ok(true) => {
      // maybe_changed_after returned true AND already recomputed this cell.
      // The value is now up-to-date in self.value.
      self.rt.record_dependency(self.cell_id)
      Ok(self.value.unwrap())
    }
    Err(e) => Err(e)
  }
}
```

Both `Ok(false)` and `Ok(true)` are identical. The verification algorithm internally handles the distinction; `get_result` only needs the resulting value.

### Step 2: Verify tests are green before touching the hot path

```bash
moon test -p dowdiness/incr -f memo_test.mbt
moon test -p dowdiness/incr -f backdating_test.mbt
moon test -p dowdiness/incr -f durability_wbtest.mbt
```

Expected: all pass.

### Step 3: Merge the arms

**After:**
```moonbit
Some(_) => {
  if cell.verified_at == self.rt.current_revision {
    self.rt.record_dependency(self.cell_id)
    return Ok(self.value.unwrap())
  }
  match maybe_changed_after(self.rt, self.cell_id, cell.verified_at) {
    Ok(_) => {
      self.rt.record_dependency(self.cell_id)
      Ok(self.value.unwrap())
    }
    Err(e) => Err(e)
  }
}
```

Remove the comments from both old arms (they described the distinction, which is now internal). The single comment "value is up-to-date; record dependency and return" is enough if you want one.

### Step 4: Run targeted tests

```bash
moon test -p dowdiness/incr -f memo_test.mbt
moon test -p dowdiness/incr -f backdating_test.mbt
moon test -p dowdiness/incr -f durability_wbtest.mbt
```

Expected: all pass.

### Step 5: Run full suite

```bash
moon test
```

Expected: all 123 tests pass.

### Step 6: Commit

```bash
git add memo.mbt
git commit -m "refactor: merge identical Ok arms in Memo::get_result"
```

---

## Task 4: Extract frame pop+propagate helper in `verify.mbt` (Item 10)

**Files:**
- Modify: `verify.mbt`

This task touches the correctness-critical verification loop. Read carefully before editing.

### Step 1: Run the verification-sensitive tests first

```bash
moon test -p dowdiness/incr -f backdating_test.mbt
moon test -p dowdiness/incr -f cycle_test.mbt
moon test -p dowdiness/incr -f cycle_path_test.mbt
moon test -p dowdiness/incr -f verify_path_test.mbt
moon test -p dowdiness/incr -f durability_wbtest.mbt
```

Expected: all pass. This is your baseline.

### Step 2: Understand the duplication

In `maybe_changed_after_derived` (`verify.mbt`), locate the while loop. There are two places where a frame is popped and the result propagated — the `any_dep_changed` branch (after `finish_frame_changed`) and the "all deps checked" branch (after `finish_frame_unchanged`):

**First occurrence (after finish_frame_changed, ~line 97):**
```moonbit
Ok(result) => {
  let _ = stack.pop()
  let _ = path.pop()
  if stack.length() > 0 {
    if result {
      stack[stack.length() - 1].any_dep_changed = true
    }
  } else {
    final_result = result
  }
}
```

**Second occurrence (after finish_frame_unchanged, ~line 118):**
```moonbit
let result = finish_frame_unchanged(rt, stack[top])
let _ = stack.pop()
let _ = path.pop()
if stack.length() > 0 {
  if result {
    stack[stack.length() - 1].any_dep_changed = true
  }
} else {
  final_result = result
}
```

These blocks are identical except for how `result` is computed.

### Step 3: Note the `final_result` mutation constraint

`final_result` is a `mut` local in `maybe_changed_after_derived`. To mutate it from a helper function, wrap it in a `Ref`:

Change:
```moonbit
let mut final_result = false
```
To:
```moonbit
let final_result : Ref[Bool] = { val: false }
```

And at the end of the function, change:
```moonbit
Ok(final_result)
```
To:
```moonbit
Ok(final_result.val)
```

### Step 4: Add the helper function

Add this private function directly above `maybe_changed_after_derived` in `verify.mbt`:

```moonbit
///|
/// Pop the top frame and propagate its result to the parent frame or final_result.
/// Called after both finish_frame_changed and finish_frame_unchanged.
fn pop_frame(
  stack : Array[VerifyFrame],
  path : Array[CellId],
  result : Bool,
  final_result : Ref[Bool],
) -> Unit {
  let _ = stack.pop()
  let _ = path.pop()
  if stack.length() > 0 {
    if result {
      stack[stack.length() - 1].any_dep_changed = true
    }
  } else {
    final_result.val = result
  }
}
```

### Step 5: Replace the two duplicated blocks

**First occurrence** — inside the `Ok(result) =>` arm after `finish_frame_changed`:

```moonbit
Ok(result) => {
  pop_frame(stack, path, result, final_result)
}
```

**Second occurrence** — after `finish_frame_unchanged`:

```moonbit
let result = finish_frame_unchanged(rt, stack[top])
pop_frame(stack, path, result, final_result)
```

The `continue` statements that follow each block are unchanged.

### Step 6: Type-check

```bash
moon check
```

Expected: no errors. If you see a type mismatch on `final_result`, verify you updated all three locations: the `let` declaration, the two `pop_frame` call sites, and the `Ok(final_result.val)` return.

### Step 7: Run targeted tests

```bash
moon test -p dowdiness/incr -f backdating_test.mbt
moon test -p dowdiness/incr -f cycle_test.mbt
moon test -p dowdiness/incr -f cycle_path_test.mbt
moon test -p dowdiness/incr -f verify_path_test.mbt
moon test -p dowdiness/incr -f durability_wbtest.mbt
```

Expected: all pass.

### Step 8: Run full suite

```bash
moon test
```

Expected: all 123 tests pass.

### Step 9: Commit

```bash
git add verify.mbt
git commit -m "refactor: extract pop_frame helper in maybe_changed_after_derived"
```

---

## Final check

```bash
moon test
```

Expected: all 123 tests pass. All four items complete.
