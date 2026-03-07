# Cells Simplification Implementation Plan

> **For Claude:** REQUIRED SUB-SKILL: Use superpowers:executing-plans to implement this plan task-by-task.

**Goal:** Split `runtime.mbt` into focused files, deduplicate validation patterns, and extract dispose cleanup methods — all without behavioral changes.

**Architecture:** Pure refactor. Extract code blocks from `runtime.mbt` (1,101 LOC) into `batch.mbt`, `tracking.mbt` (merge), and `introspection.mbt`. Add `validate_cell`/`validate_cell_soft` helpers to replace 10 duplicated checks. Add `clear_slot()` methods on push data structs.

**Tech Stack:** MoonBit, `moon test` (305 tests must pass after every task)

**Design doc:** `docs/plans/2026-03-07-cells-simplification-design.md`

---

### Task 1: Add validate_cell and validate_cell_soft helpers

**Files:**
- Modify: `cells/runtime.mbt` (add two new methods around line 310, before `get_changed_at`)

**Step 1: Add the two helper methods**

Insert before `get_changed_at` (line 312):

```moonbit
///|
/// Validates that a CellId belongs to this runtime and is within bounds.
/// Aborts with a descriptive message on failure.
fn Runtime::validate_cell(self : Runtime, id : CellId, caller : String) -> Unit {
  if id.runtime_id != self.core.runtime_id {
    abort("Cell belongs to a different Runtime")
  }
  if id.id < 0 || id.id >= self.core.cell_ops.length() {
    abort(caller + ": cell_id out of bounds: " + id.id.to_string())
  }
}

///|
/// Returns true if the CellId belongs to this runtime and is within bounds.
/// Non-aborting variant for methods that return None/[] on invalid input.
fn Runtime::validate_cell_soft(self : Runtime, id : CellId) -> Bool {
  id.runtime_id == self.core.runtime_id &&
  id.id >= 0 &&
  id.id < self.core.cell_ops.length()
}
```

**Step 2: Run tests**

Run: `moon test`
Expected: 305 passed, 0 failed

**Step 3: Commit**

```
git add cells/runtime.mbt
git commit -m "refactor: add validate_cell and validate_cell_soft helpers"
```

---

### Task 2: Replace validation boilerplate with validate_cell

**Files:**
- Modify: `cells/runtime.mbt` — 8 methods that abort on invalid IDs

**Step 1: Replace each method's validation block**

Replace `get_changed_at` (currently lines 316-324):
```moonbit
///|
fn Runtime::get_changed_at(self : Runtime, id : CellId) -> Revision {
  self.validate_cell(id, "get_changed_at")
  self.core.cell_ops[id.id].changed_at()
}
```

Replace `get_durability` (currently lines 328-336):
```moonbit
///|
fn Runtime::get_durability(self : Runtime, id : CellId) -> Durability {
  self.validate_cell(id, "get_durability")
  self.core.cell_ops[id.id].durability()
}
```

Replace `get_pull_signal` (currently lines 362-376):
```moonbit
///|
fn Runtime::get_pull_signal(self : Runtime, id : CellId) -> PullSignalData {
  self.validate_cell(id, "get_pull_signal")
  match self.core.cell_index[id.id] {
    PullSignal(idx) => self.pull.signals[idx]
    _ =>
      abort(
        "Expected signal cell but found different kind: " + id.id.to_string(),
      )
  }
}
```

Replace `get_pull_memo` (currently lines 384-396):
```moonbit
///|
fn Runtime::get_pull_memo(self : Runtime, id : CellId) -> PullMemoData {
  self.validate_cell(id, "get_pull_memo")
  match self.core.cell_index[id.id] {
    PullMemo(idx) => self.pull.memos[idx]
    _ =>
      abort("Expected memo cell but found different kind: " + id.id.to_string())
  }
}
```

Replace `get_hybrid_memo` (currently lines 400-415):
```moonbit
///|
fn Runtime::get_hybrid_memo(self : Runtime, id : CellId) -> HybridMemoData {
  self.validate_cell(id, "get_hybrid_memo")
  match self.core.cell_index[id.id] {
    HybridMemo(idx) => self.push.hybrid_memos[idx]
    _ =>
      abort(
        "Expected hybrid memo cell but found different kind: " +
        id.id.to_string(),
      )
  }
}
```

Replace `get_subscribers` (currently lines 423-431):
```moonbit
///|
fn Runtime::get_subscribers(self : Runtime, cell_id : CellId) -> Iter[CellId] {
  self.validate_cell(cell_id, "get_subscribers")
  self.core.cell_ops[cell_id.id].subscribers().iter()
}
```

Replace `remove_subscriber` (currently lines 435-447):
```moonbit
///|
fn Runtime::remove_subscriber(
  self : Runtime,
  dep : CellId,
  subscriber : CellId,
) -> Unit {
  self.validate_cell(dep, "remove_subscriber")
  self.core.cell_ops[dep.id].subscribers().remove(subscriber)
}
```

Replace `add_subscriber` (currently lines 451-463):
```moonbit
///|
fn Runtime::add_subscriber(
  self : Runtime,
  dep : CellId,
  subscriber : CellId,
) -> Unit {
  self.validate_cell(dep, "add_subscriber")
  self.core.cell_ops[dep.id].subscribers().add(subscriber)
}
```

**Step 2: Run tests**

Run: `moon test`
Expected: 305 passed, 0 failed

**Step 3: Commit**

```
git add cells/runtime.mbt
git commit -m "refactor: replace 8 validation blocks with validate_cell helper"
```

---

### Task 3: Replace validation in cell_info and dependents with validate_cell_soft

**Files:**
- Modify: `cells/runtime.mbt` — `cell_info` and `dependents` methods

**Step 1: Replace validation in cell_info**

Replace the two guard clauses at the top of `cell_info` (currently lines 541-546):
```moonbit
pub fn Runtime::cell_info(self : Runtime, id : CellId) -> CellInfo? {
  if not(self.validate_cell_soft(id)) {
    return None
  }
  // ... rest unchanged
```

**Step 2: Replace validation in dependents**

Replace the two guard clauses at the top of `dependents` (currently lines 608-613):
```moonbit
pub fn Runtime::dependents(self : Runtime, id : CellId) -> Array[CellId] {
  if not(self.validate_cell_soft(id)) {
    return []
  }
  snapshot_subscribers(self.core.cell_ops[id.id].subscribers())
}
```

**Step 3: Run tests**

Run: `moon test`
Expected: 305 passed, 0 failed

**Step 4: Commit**

```
git add cells/runtime.mbt
git commit -m "refactor: replace validation in cell_info/dependents with validate_cell_soft"
```

---

### Task 4: Add clear_slot methods for dispose cleanup

**Files:**
- Modify: `cells/push_reactive.mbt` — add `PushReactiveData::clear_slot`
- Modify: `cells/push_effect.mbt` — add `PushEffectData::clear_slot`
- Modify: `cells/runtime.mbt` — update `dispose_reactive` and `dispose_effect`

**Step 1: Add clear_slot to PushReactiveData**

Append after the `level` CellOps impl (after line 61 in `push_reactive.mbt`):

```moonbit
///|
/// Clears all mutable fields to release captured closures and graph edges.
/// Called by `Runtime::dispose_reactive` after removing subscriber links.
fn PushReactiveData::clear_slot(self : PushReactiveData) -> Unit {
  self.compute = () => false
  self.sources = []
  self.subscribers.clear()
  self.label = None
  self.dirty = false
}
```

**Step 2: Add clear_slot to PushEffectData**

Append after the `level` CellOps impl (after line 62 in `push_effect.mbt`):

```moonbit
///|
/// Clears all mutable fields to release captured closures and graph edges.
/// Called by `Runtime::dispose_effect` after removing subscriber links.
fn PushEffectData::clear_slot(self : PushEffectData) -> Unit {
  self.execute = () => ()
  self.sources = []
  self.subscribers.clear()
  self.label = None
  self.dirty = false
}
```

**Step 3: Update dispose_reactive to use clear_slot**

Replace the field-clearing lines in `dispose_reactive` (currently lines 1048-1055 in `runtime.mbt`):

```moonbit
fn Runtime::dispose_reactive(self : Runtime, cell_id : CellId) -> Unit {
  if cell_id.id < 0 || cell_id.id >= self.core.cell_index.length() {
    return
  }
  match self.core.cell_index[cell_id.id] {
    PushReactive(idx) => {
      let reactive = self.push.reactives[idx]
      for dep in reactive.sources {
        self.remove_subscriber(dep, cell_id)
      }
      self.core.cell_index[cell_id.id] = Disposed
      reactive.clear_slot()
      self.push.free_reactives.push(idx)
      self.push.node_count = self.push.node_count - 1
    }
    _ => ()
  }
}
```

**Step 4: Update dispose_effect to use clear_slot**

Replace the field-clearing lines in `dispose_effect` (currently lines 1077-1083 in `runtime.mbt`):

```moonbit
fn Runtime::dispose_effect(self : Runtime, cell_id : CellId) -> Unit {
  if cell_id.id < 0 || cell_id.id >= self.core.cell_index.length() {
    return
  }
  match self.core.cell_index[cell_id.id] {
    PushEffect(idx) => {
      let effect = self.push.effects[idx]
      for dep in effect.sources {
        self.remove_subscriber(dep, cell_id)
      }
      self.core.cell_index[cell_id.id] = Disposed
      effect.clear_slot()
      self.push.free_effects.push(idx)
      self.push.node_count = self.push.node_count - 1
    }
    _ => ()
  }
}
```

**Step 5: Run tests**

Run: `moon test`
Expected: 305 passed, 0 failed

**Step 6: Commit**

```
git add cells/push_reactive.mbt cells/push_effect.mbt cells/runtime.mbt
git commit -m "refactor: extract clear_slot methods for dispose cleanup"
```

---

### Task 5: Create batch.mbt — extract batch logic from runtime.mbt

**Files:**
- Create: `cells/batch.mbt`
- Modify: `cells/runtime.mbt` — remove extracted code

**Step 1: Create `cells/batch.mbt`**

Move these items from `runtime.mbt` to a new `cells/batch.mbt`:

1. `BatchUndo` struct (lines 26-29)
2. `BatchFrame` struct + `new` + `has_undo_for` (lines 33-46)
3. `Runtime::batch` (lines 705-727)
4. `Runtime::batch_result` (lines 735-740)
5. `Runtime::rollback_current_batch_frame` (lines 744-756)
6. `Runtime::complete_batch_frame_success` (lines 762-778)
7. `Runtime::commit_batch` (lines 786-838)
8. `Runtime::record_batch_signal` (lines 850-855)
9. `Runtime::record_batch_rollback` (lines 860-877)
10. `Runtime::remove_batch_signal` (lines 885-899)
11. `Runtime::recompute_batch_max_durability` (lines 903-912)

Remove all of the above from `runtime.mbt`.

**Step 2: Run tests**

Run: `moon test`
Expected: 305 passed, 0 failed

**Step 3: Commit**

```
git add cells/batch.mbt cells/runtime.mbt
git commit -m "refactor: extract batch logic into batch.mbt"
```

---

### Task 6: Merge tracking methods into tracking.mbt

**Files:**
- Modify: `cells/tracking.mbt` — append methods from runtime.mbt
- Modify: `cells/runtime.mbt` — remove extracted code

**Step 1: Append to `cells/tracking.mbt`**

Move these items from `runtime.mbt` and append after the existing `ActiveQuery::record` method:

1. `Tracker` impl for `record_dependency` (lines 924-929)
2. `Tracker` impl for `push_tracking` (lines 940-943)
3. `Tracker` impl for `pop_tracking` (lines 958-968)
4. `Runtime::begin_tracking` (lines 976-978)
5. `Runtime::end_tracking` (lines 989-992)
6. `Runtime::finish_tracking` (lines 1005-1030)
7. `Runtime::collect_tracking_path` (lines 1095-1101)

Remove all of the above from `runtime.mbt`.

**Important:** The `Tracker` trait declaration and `RevisionManager` trait declaration stay in `runtime.mbt` — they define the capability traits. Only the `impl` blocks and helper methods move.

**Step 2: Run tests**

Run: `moon test`
Expected: 305 passed, 0 failed

**Step 3: Commit**

```
git add cells/tracking.mbt cells/runtime.mbt
git commit -m "refactor: merge tracking methods into tracking.mbt"
```

---

### Task 7: Create introspection.mbt — extract introspection logic

**Files:**
- Create: `cells/introspection.mbt`
- Modify: `cells/runtime.mbt` — remove extracted code

**Step 1: Create `cells/introspection.mbt`**

Move these items from `runtime.mbt`:

1. `CellInfo` struct (lines 218-226)
2. `snapshot_subscribers` helper (lines 580-588)
3. `Runtime::cell_info` (lines 540-576)
4. `Runtime::dependents` (lines 607-615)
5. `Runtime::collect_in_progress_path` (lines 297-310)

Remove all of the above from `runtime.mbt`.

**Step 2: Run tests**

Run: `moon test`
Expected: 305 passed, 0 failed

**Step 3: Commit**

```
git add cells/introspection.mbt cells/runtime.mbt
git commit -m "refactor: extract introspection logic into introspection.mbt"
```

---

### Task 8: Update interfaces, format, and verify

**Files:**
- Modify: Various `.mbti` files (auto-generated)

**Step 1: Update interfaces**

Run: `moon info`

**Step 2: Format**

Run: `moon fmt`

**Step 3: Check for API changes**

Run: `git diff *.mbti`
Expected: No changes (all methods stay public with same signatures)

**Step 4: Run full test suite one final time**

Run: `moon test`
Expected: 305 passed, 0 failed

**Step 5: Commit if any formatting changes**

```
git add -A
git commit -m "chore: update interfaces and format after cells simplification"
```

---

### Task 9: Update design doc status

**Files:**
- Modify: `docs/plans/2026-03-07-cells-simplification-design.md`

**Step 1: Mark complete and archive**

Update status to `**Status:** Complete`.

Move: `git mv docs/plans/2026-03-07-cells-simplification-design.md docs/archive/completed-phases/`

Also move the impl plan: `git mv docs/plans/2026-03-08-cells-simplification-impl.md docs/archive/completed-phases/`

Update `docs/README.md`: move entry from Active Plans to Archive.

**Step 2: Commit**

```
git add docs/
git commit -m "docs: archive cells simplification plans as complete"
```
