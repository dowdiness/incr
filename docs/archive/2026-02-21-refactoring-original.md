# Original Refactoring Plan Implementation

> **Status: ✅ COMPLETED** — All 8 tasks implemented and verified. 128 tests passing.

**Goal:** Execute the 8 internal quality improvements from `refactoring-plan.md` — no new features, no API changes, all 128 tests green throughout.

**Architecture:** Each task is independent. Order goes from highest impact to lowest, saving correctness-critical changes for last. TDD throughout — confirm baseline green, make the change, run targeted tests, commit.

**Tech Stack:** MoonBit · `moon test` · `moon check` · `moon info`

---

## Task 1: Consolidate revision-bump logic (Item 1) ✅

**Files:**
- Modify: `runtime.mbt` (bump_revision L261–275, commit_batch L353–366)
- Modify: `signal.mbt` (set_unconditional L186–201)

### Step 1: Baseline

```bash
moon test -p dowdiness/incr -f batch_wbtest.mbt
moon test -p dowdiness/incr -f durability_wbtest.mbt
```

Both must pass before touching anything.

### Step 2: Extract `advance_revision` helper

Add this private function in `runtime.mbt`, directly **above** `bump_revision` (before line 261):

```moonbit
///|
/// Advance the global revision counter and record which durability level changed.
/// Updates current_revision and all durability_last_changed entries up to dur_idx.
/// Callers must ensure this is only called outside of a batch (batch_depth == 0).
fn Runtime::advance_revision(self : Runtime, durability : Durability) -> Unit {
  self.current_revision = self.current_revision.next()
  let dur_idx = durability.index()
  for i = 0; i <= dur_idx; i = i + 1 {
    self.durability_last_changed[i] = self.current_revision
  }
}
```

### Step 3: Update `bump_revision` to use it

Replace the non-batch path of `bump_revision` (the lines after `return`):

**Before (lines 269–274):**
```moonbit
  self.current_revision = self.current_revision.next()
  // Update this durability level and all lower durability levels
  let dur_idx = durability.index()
  for i = 0; i <= dur_idx; i = i + 1 {
    self.durability_last_changed[i] = self.current_revision
  }
```

**After:**
```moonbit
  self.advance_revision(durability)
```

The full `bump_revision` should now be:
```moonbit
fn Runtime::bump_revision(self : Runtime, durability : Durability) -> Unit {
  if self.batch_depth > 0 {
    // Track the maximum durability seen during this batch
    if durability > self.batch_max_durability {
      self.batch_max_durability = durability
    }
    return
  }
  self.advance_revision(durability)
}
```

### Step 4: Update `commit_batch` phase 2 to use `advance_revision`

In `commit_batch`, replace the phase 2 revision-bump block. Find these lines (~353–359):
```moonbit
    let durability = self.batch_max_durability
    self.current_revision = self.current_revision.next()
    let dur_idx = durability.index()
    for i = 0; i <= dur_idx; i = i + 1 {
      self.durability_last_changed[i] = self.current_revision
    }
```

Replace with:
```moonbit
    self.advance_revision(self.batch_max_durability)
```

Also remove the now-unused `let durability = self.batch_max_durability` line. And the sweep loop below uses `self.current_revision` directly — that still works since `advance_revision` updates `self.current_revision`.

### Step 5: Extract `mark_input_changed` helper

Add this private function in `runtime.mbt`, directly below `advance_revision`:

```moonbit
///|
/// Mark an input cell as changed at the current revision.
/// Sets both changed_at and verified_at to current_revision.
/// Must be called after advance_revision so current_revision is already updated.
fn Runtime::mark_input_changed(self : Runtime, id : CellId) -> CellMeta {
  let meta = self.get_cell(id)
  meta.changed_at = self.current_revision
  meta.verified_at = self.current_revision
  meta
}
```

### Step 6: Update `set_unconditional` to use `mark_input_changed`

In `signal.mbt`, inside the non-batch branch of `Signal::set_unconditional` (~L190–194):

**Before:**
```moonbit
    self.value = new_value
    self.rt.bump_revision(self.durability)
    let meta = self.rt.get_cell(self.cell_id)
    meta.changed_at = self.rt.current_revision
    meta.verified_at = self.rt.current_revision
```

**After:**
```moonbit
    self.value = new_value
    self.rt.bump_revision(self.durability)
    let meta = self.rt.mark_input_changed(self.cell_id)
    match meta.on_change {
      Some(f) => f()
      None => ()
    }
    self.rt.fire_on_change()
```

### Step 7: Update `commit_batch` sweep to use `mark_input_changed`

In `commit_batch`, replace the sweep loop (~L362–366):

**Before:**
```moonbit
    // Sweep changed signals
    let rev = self.current_revision
    for i = 0; i < changed_ids.length(); i = i + 1 {
      let meta = self.get_cell(changed_ids[i])
      meta.changed_at = rev
      meta.verified_at = rev
    }
```

**After:**
```moonbit
    // Sweep changed signals and collect callbacks in a single pass.
    let callbacks : Array[() -> Unit] = []
    for id in changed_ids {
      let meta = self.mark_input_changed(id)
      match meta.on_change {
        Some(f) => callbacks.push(f)
        None => ()
      }
    }
```

(The `let rev = self.current_revision` line can be removed since `mark_input_changed` reads `self.current_revision` internally. Callbacks are collected and fired after the sweep.)

### Step 8: Type-check

```bash
moon check
```

Expected: no errors.

### Step 9: Run targeted tests

```bash
moon test -p dowdiness/incr -f batch_wbtest.mbt
moon test -p dowdiness/incr -f durability_wbtest.mbt
```

Both must pass.

### Step 10: Run full suite

```bash
moon test
```

Expected: 128 tests pass.

### Step 11: Commit

```bash
git add runtime.mbt signal.mbt
git commit -m "refactor: extract advance_revision and mark_input_changed helpers"
```

---

## Task 2: Replace silent fallbacks with assertions (Item 2) ✅

**Files:**
- Modify: `verify.mbt` (finish_frame_changed L228)
- Modify: `runtime.mbt` (commit_batch None arm L347)
- Create or modify: `verify_wbtest.mbt` (new panic test)
- Modify: `batch_wbtest.mbt` (new panic test)

### Step 1: Baseline

```bash
moon test
```

Expected: 128 pass.

### Step 2: Replace the fallback in `finish_frame_changed`

In `verify.mbt`, `finish_frame_changed`, the final `None` arm (~line 228):

**Before:**
```moonbit
    None => Ok(true)
```

**After:**
```moonbit
    None => abort("Derived cell missing recompute_and_check — internal invariant violated")
```

### Step 3: Replace the fallback in `commit_batch`

In `runtime.mbt`, `commit_batch`, Phase 1 loop, the `None` arm (~line 347):

**Before:**
```moonbit
      None => ()
```

**After:**
```moonbit
      None => abort("Batched signal missing commit_pending — internal invariant violated")
```

### Step 4: Run full suite to confirm no existing test hits these paths

```bash
moon test
```

Expected: 128 tests pass. These are invariant violations — no normal test should abort.

### Step 5: Add panic test for `finish_frame_changed` None arm

Create `verify_wbtest.mbt` (new file):

```moonbit
///|
// Trigger finish_frame_changed with a Derived cell whose recompute_and_check
// is None — simulates internal state corruption.
test "panic finish_frame_changed: Derived cell with None recompute_and_check aborts" {
  let rt = Runtime::new()
  let sig = Signal::new(rt, 0)
  let memo = Memo::new(rt, () => sig.get() + 1)
  // Force first computation to populate cell state
  let _ = memo.get_result()
  // Corrupt internal state: clear the type-erased recompute closure
  let meta = rt.get_cell(memo.id())
  meta.recompute_and_check = None
  // Trigger a re-verification: change sig so the memo is stale
  sig.set(1)
  // get_result calls maybe_changed_after which calls finish_frame_changed
  // with the corrupted cell — must abort
  let _ = memo.get_result()
}
```

### Step 6: Run the new panic test

```bash
moon test -p dowdiness/incr -f verify_wbtest.mbt
```

Expected: 1 passed (the abort fires as expected).

### Step 7: Add panic test for `commit_batch` None arm

Append to `batch_wbtest.mbt`:

```moonbit
///|
// Trigger commit_batch with a signal whose commit_pending is None —
// simulates internal state corruption (missing commit closure).
test "panic commit_batch: signal with None commit_pending aborts" {
  let rt = Runtime::new()
  let sig = Signal::new(rt, 0)
  // Manually enter batch mode by directly setting batch_depth
  rt.batch_depth = 1
  // set() detects batch_depth > 0 and calls set_batch, which registers
  // commit_pending and enqueues the cell id in batch_pending_signals
  sig.set(1)
  // Corrupt the commit_pending closure
  let meta = rt.get_cell(sig.id())
  meta.commit_pending = None
  // Manually exit batch and trigger commit_batch
  rt.batch_depth = 0
  rt.commit_batch()
}
```

### Step 8: Run all batch whitebox tests

```bash
moon test -p dowdiness/incr -f batch_wbtest.mbt
```

Expected: all pass (including the new panic test).

### Step 9: Run full suite

```bash
moon test
```

Expected: 128 tests pass (2 new panic tests added).

### Step 10: Commit

```bash
git add verify.mbt runtime.mbt verify_wbtest.mbt batch_wbtest.mbt
git commit -m "fix: replace silent None fallbacks with abort assertions"
```

---

## Task 3: Simplify `Signal::get_result` (Item 4) ✅

**Files:**
- Modify: `signal.mbt` (get_result L98–101)

### Step 1: Baseline

```bash
moon test
```

Expected: all pass.

### Step 2: Replace `get_result` body

In `signal.mbt`, `Signal::get_result` (~L98–101):

**Before:**
```moonbit
pub fn[T] Signal::get_result(self : Signal[T]) -> Result[T, CycleError] {
  self.rt.record_dependency(self.cell_id)
  Ok(self.value)
}
```

**After:**
```moonbit
pub fn[T] Signal::get_result(self : Signal[T]) -> Result[T, CycleError] {
  Ok(self.get())
}
```

`get()` already calls `record_dependency` and returns `self.value`, so the behavior is identical.

### Step 3: Run full suite

```bash
moon test
```

Expected: all pass.

### Step 4: Commit

```bash
git add signal.mbt
git commit -m "refactor: simplify Signal::get_result to delegate to get()"
```

---

## Task 4: Improve `Memo::get` abort message (Item 5) ✅

**Files:**
- Modify: `memo.mbt` (Memo::get L95–101)

### Step 1: Baseline

```bash
moon test -p dowdiness/incr -f cycle_test.mbt
```

Expected: all pass.

### Step 2: Replace the abort message

In `memo.mbt`, `Memo::get`, the `Err` branch (~L95–101):

**Before:**
```moonbit
    Err(CycleDetected(cell, path)) =>
      abort(
        "Cycle detected at cell " +
        cell.to_string() +
        ", path length: " +
        path.length().to_string(),
      )
```

**After:**
```moonbit
    Err(e) => abort(e.format_path(self.rt))
```

The full `Memo::get` function becomes:
```moonbit
pub fn[T : Eq] Memo::get(self : Memo[T]) -> T {
  match self.get_result() {
    Ok(value) => value
    Err(e) => abort(e.format_path(self.rt))
  }
}
```

`format_path` produces output like `"Cycle detected: Cell[0] → Cell[1] → Cell[0]"` — more useful than the current message.

### Step 3: Add a comment noting the test gap

Directly above `Memo::get`, add a doc note (or inline comment) that cycle tests use `get_result`, not `get`:

Inside the `# Panics` section of the doc comment (around line 90), append:
```moonbit
/// Note: existing cycle tests use `get_result()` and do not exercise this abort path.
```

### Step 4: Run full suite

```bash
moon test
```

Expected: all pass. The existing panic tests in `cycle_test.mbt` (which call `get()`) still pass because they abort with the new message format.

### Step 5: Commit

```bash
git add memo.mbt
git commit -m "fix: improve Memo::get cycle abort message via format_path"
```

---

## Task 5: Add runtime ownership check in `get_cell` (Item 3) ✅

**Files:**
- Modify: `runtime.mbt` (get_cell L138–147)

### Step 1: Baseline

```bash
moon test
```

Expected: all pass.

### Step 2: Add guards to `get_cell`

In `runtime.mbt`, `Runtime::get_cell` (~L138):

**Before:**
```moonbit
fn Runtime::get_cell(self : Runtime, id : CellId) -> CellMeta {
  if id.id < self.cells.length() {
    match self.cells[id.id] {
      Some(meta) => meta
      None => abort("Cell not found: " + id.id.to_string())
    }
  } else {
    abort("Cell not found: " + id.id.to_string())
  }
}
```

**After:**
```moonbit
fn Runtime::get_cell(self : Runtime, id : CellId) -> CellMeta {
  if id.runtime_id != self.runtime_id {
    abort("Cell belongs to a different Runtime")
  }
  if id.id < 0 {
    abort("Invalid cell id: " + id.id.to_string())
  }
  if id.id < self.cells.length() {
    match self.cells[id.id] {
      Some(meta) => meta
      None => abort("Cell not found: " + id.id.to_string())
    }
  } else {
    abort("Cell not found: " + id.id.to_string())
  }
}
```

### Step 3: Run full suite

```bash
moon test
```

Expected: all pass. No existing test uses cross-runtime or negative cell IDs with `get_cell`.

### Step 4: Commit

```bash
git add runtime.mbt
git commit -m "fix: add runtime ownership and negative-id guards to get_cell"
```

---

## Task 6: Use idiomatic loop patterns (Item 8) ✅

**Files:**
- Modify: `memo.mbt` (`compute_durability` L234–240)
- Modify: `runtime.mbt` (`commit_batch` callback collection L369–375)

The `format_path` loop in `cycle.mbt` uses `i > 0` for separator logic and cannot be trivially converted — leave it C-style.

The loops in `verify.mbt` use positional access (`stack[top]`) — leave those C-style.

### Step 1: Verify `for-in` over Array is supported

Run a quick smoke test before editing:

```bash
moon check
```

Expected: clean. The existing codebase (e.g., `for frame in self.tracking_stack`) confirms `for-in` works on `Array`.

### Step 2: Convert `compute_durability` in `memo.mbt`

Find `compute_durability` (~L232–241):

**Before:**
```moonbit
  let mut min_dur = High
  for i = 0; i < deps.length(); i = i + 1 {
    let dep_cell = rt.get_cell(deps[i])
    let dep_dur = dep_cell.durability
    if dep_dur < min_dur {
      min_dur = dep_dur
    }
  }
  min_dur
```

**After:**
```moonbit
  let mut min_dur = High
  for dep_id in deps {
    let dep_cell = rt.get_cell(dep_id)
    if dep_cell.durability < min_dur {
      min_dur = dep_cell.durability
    }
  }
  min_dur
```

### Step 3: Convert callback collection loop in `runtime.mbt`

Find the callback collection loop in `commit_batch` (~L369–375):

**Before:**
```moonbit
    let callbacks : Array[() -> Unit] = []
    for i = 0; i < changed_ids.length(); i = i + 1 {
      let meta = self.get_cell(changed_ids[i])
      match meta.on_change {
        Some(f) => callbacks.push(f)
        None => ()
      }
    }
```

**After:**
```moonbit
    let callbacks : Array[() -> Unit] = []
    for id in changed_ids {
      let meta = self.get_cell(id)
      match meta.on_change {
        Some(f) => callbacks.push(f)
        None => ()
      }
    }
```

### Step 4: Type-check

```bash
moon check
```

Expected: no errors.

### Step 5: Run full suite

```bash
moon test
```

Expected: all tests pass.

### Step 6: Commit

```bash
git add memo.mbt runtime.mbt
git commit -m "refactor: convert safe C-style loops to for-in in memo.mbt and runtime.mbt"
```

---

## Task 7: Demote unused pipeline traits (Item 7) ✅

**Files:**
- Modify: `traits.mbt` (remove pipeline traits section L148–178)
- Create: `pipeline_traits.mbt` (contains the four traits with experimental doc comments)

### Step 1: Baseline

```bash
moon check
moon test
```

Both must pass.

### Step 2: Create `pipeline_traits.mbt`

Create a new file `pipeline_traits.mbt` with the four pipeline traits, adding experimental doc comments:

```moonbit
// === Pipeline Traits ===
// These traits define the stages of a compilation/processing pipeline.
// They are experimental and may change or be removed in future versions.
// No production usage — currently only exercised by test fixtures (CalcPipeline).

///|
/// **Experimental.** A system that has source text input.
///
/// Implement this trait to provide get/set access to source text
/// backed by an incremental Signal.
pub(open) trait Sourceable {
  set_source_text(Self, String) -> Unit
  source_text(Self) -> String
}

///|
/// **Experimental.** A system that can parse and report parse errors.
pub(open) trait Parseable {
  parse_errors(Self) -> Array[String]
}

///|
/// **Experimental.** A system that can check (type-check, lint, etc.) and report errors.
pub(open) trait Checkable {
  check_errors(Self) -> Array[String]
}

///|
/// **Experimental.** A system that can execute/evaluate and produce output.
pub(open) trait Executable {
  run(Self) -> Array[String]
}
```

### Step 3: Remove the pipeline traits section from `traits.mbt`

In `traits.mbt`, delete everything from the `// === Pipeline Traits ===` comment through the end of `Executable` (lines 148–178 inclusive):

```moonbit
// === Pipeline Traits ===
// These traits define the stages of a compilation/processing pipeline.
// Users implement them for their own database types and compose them as needed.

///|
/// A system that has source text input.
///
/// Implement this trait to provide get/set access to source text
/// backed by an incremental Signal.
pub(open) trait Sourceable {
  set_source_text(Self, String) -> Unit
  source_text(Self) -> String
}

///|
/// A system that can parse and report parse errors.
pub(open) trait Parseable {
  parse_errors(Self) -> Array[String]
}

///|
/// A system that can check (type-check, lint, etc.) and report errors.
pub(open) trait Checkable {
  check_errors(Self) -> Array[String]
}

///|
/// A system that can execute/evaluate and produce output.
pub(open) trait Executable {
  run(Self) -> Array[String]
}
```

Delete all of the above. `traits.mbt` should end after `pub fn[Db : Database] batch`.

### Step 4: Type-check and regenerate interface file

```bash
moon check
```

Expected: no errors (all `.mbt` files in the same package, so `traits_test.mbt` still sees the traits).

```bash
moon info
```

This regenerates `pkg.generated.mbti`. Open it and confirm:
- The four pipeline traits now appear in `pkg.generated.mbti` (they moved files, not packages)
- No unintended removals from the public interface

### Step 5: Run full suite

```bash
moon test
```

Expected: all tests pass.

### Step 6: Commit

```bash
git add traits.mbt pipeline_traits.mbt pkg.generated.mbti
git commit -m "refactor: move pipeline traits to pipeline_traits.mbt with experimental doc comments"
```

---

## Task 8: Centralize cycle-path construction (Item 6) ✅

**Files:**
- Modify: `cycle.mbt` (add `CycleError::from_path`)
- Modify: `runtime.mbt` (add `Runtime::collect_tracking_path`)
- Modify: `memo.mbt` (`Memo::force_recompute` cycle path block)
- Modify: `verify.mbt` (`try_start_verify` cycle path block)

**Risk: Medium.** Run the full test suite after every sub-step. The cycle path logic is correctness-critical.

### Step 1: Run baseline cycle tests

```bash
moon test -p dowdiness/incr -f cycle_test.mbt
moon test -p dowdiness/incr -f cycle_path_test.mbt
moon test -p dowdiness/incr -f verify_path_test.mbt
```

All must pass. This is your correctness baseline.

### Step 2: Add `CycleError::from_path` to `cycle.mbt`

Add this private function at the **end** of `cycle.mbt` (after `format_cell`):

```moonbit
///|
/// Construct a CycleError from a path of cell IDs and the cell that closes the cycle.
///
/// Copies `path`, appends `closing_id`, and returns a CycleDetected error.
/// This is path-source agnostic: callers provide whatever path they've collected
/// (tracking stack IDs or verification path IDs) without exposing runtime internals.
fn CycleError::from_path(
  path : Array[CellId],
  closing_id : CellId,
) -> CycleError {
  let full_path = path.copy()
  full_path.push(closing_id)
  CycleDetected(closing_id, full_path)
}
```

### Step 3: Add `Runtime::collect_tracking_path` to `runtime.mbt`

Add this private function near the other tracking helpers in `runtime.mbt` (after `pop_tracking`, wherever that is):

```moonbit
///|
/// Collect cell IDs from the current tracking stack.
///
/// Returns the cell IDs of all active computation frames in order,
/// for use in cycle error diagnostics. Does not modify the stack.
fn Runtime::collect_tracking_path(self : Runtime) -> Array[CellId] {
  let path : Array[CellId] = []
  for frame in self.tracking_stack {
    path.push(frame.cell_id)
  }
  path
}
```

### Step 4: Type-check

```bash
moon check
```

Expected: clean. Neither helper is called yet, so no breakage.

### Step 5: Update `Memo::force_recompute`

In `memo.mbt`, `Memo::force_recompute`, the `in_progress` cycle detection block (~L168–178):

**Before:**
```moonbit
  if cell.in_progress {
    // Build the full cycle path from the tracking stack
    let path : Array[CellId] = []
    // Collect cell IDs from all frames in the tracking stack
    for i = 0; i < self.rt.tracking_stack.length(); i = i + 1 {
      path.push(self.rt.tracking_stack[i].cell_id)
    }
    // Append current cell to show the cycle closes
    path.push(cell.id)
    return Err(CycleDetected(cell.id, path))
  }
```

**After:**
```moonbit
  if cell.in_progress {
    return Err(CycleError::from_path(self.rt.collect_tracking_path(), cell.id))
  }
```

### Step 6: Run cycle tests after memo change

```bash
moon test -p dowdiness/incr -f cycle_test.mbt
moon test -p dowdiness/incr -f cycle_path_test.mbt
```

Must pass before touching verify.mbt.

### Step 7: Update `try_start_verify`

In `verify.mbt`, `try_start_verify`, the `in_progress` cycle detection block (~L193–200):

**Before:**
```moonbit
  if cell.in_progress {
    // Cycle detected! Push the current cell to path to show the full cycle
    let full_path = Array::new(capacity=path.length() + 1)
    for i = 0; i < path.length(); i = i + 1 {
      full_path.push(path[i])
    }
    full_path.push(cell.id)
    return Err(CycleDetected(cell.id, full_path))
  }
```

**After:**
```moonbit
  if cell.in_progress {
    // Cycle detected! Build the full path and return an error.
    return Err(CycleError::from_path(path, cell.id))
  }
```

### Step 8: Run cycle and verify tests

```bash
moon test -p dowdiness/incr -f cycle_test.mbt
moon test -p dowdiness/incr -f cycle_path_test.mbt
moon test -p dowdiness/incr -f verify_path_test.mbt
```

All must pass.

### Step 9: Run full suite

```bash
moon test
```

Expected: all tests pass.

### Step 10: Commit

```bash
git add cycle.mbt runtime.mbt memo.mbt verify.mbt
git commit -m "refactor: centralize cycle-path construction via CycleError::from_path"
```

---

## Final verification ✅

```bash
moon test
moon check
```

All 128 tests pass, no type errors. All 8 original refactoring items complete.
