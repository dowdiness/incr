# Kernel + Mode Engines Implementation Plan

**Status:** Complete

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Formalize the Kernel + Mode Engines architecture by eliminating three cross-engine couplings — the datalog engine calling the push engine directly, pull_verify reading datalog-owned state, and the dead `dirty` field on `MemoData` left over from an abandoned hybrid design.

**Architecture:** `RuntimeCore` is the kernel: shared revision counter, dispatch tables, batch state, and cross-cutting flags. `PullState`, `PushState`, and `DatalogState` are separate engines that own their SoA storage and algorithms. Engines communicate only through kernel methods — no engine calls another engine's methods directly. Three changes achieve this: (1) extract a `publish_cell_changes` kernel method as the single cross-engine notification protocol, (2) move `in_fixpoint` from `DatalogState` to `RuntimeCore` so pull_verify reads kernel state not datalog state, (3) remove the vestigial `dirty` field from `MemoData` (it is never set to `true` — HybridMemo's dirty-marking was replaced by `verified_at` staleness detection in a prior refactor).

**Tech Stack:** MoonBit, `moon check`, `moon test`, `moon info && moon fmt`

---

## File Map

| File | Change |
|------|--------|
| `cells/runtime.mbt` | Add `publish_cell_changes`; add `mut in_fixpoint` to `RuntimeCore`; remove `in_fixpoint` from `DatalogState` |
| `cells/datalog_fixpoint.mbt` | Call `publish_cell_changes` instead of inline advance+propagate+fire; use `self.core.in_fixpoint` |
| `cells/verify.mbt` | Use `self.core.in_fixpoint`; remove 3 dead `not(x.dirty) &&` guards + `memo.dirty = false` |
| `cells/memo.mbt` | Use `self.rt.core.in_fixpoint`; remove dead `cell.dirty = false` |
| `cells/hybrid_memo.mbt` | Use `self.rt.core.in_fixpoint`; remove dead `not(cell.dirty) &&` guards + `cell.dirty = false` |
| `cells/datalog_relation.mbt` | Use `self.rt.core.in_fixpoint` |
| `cells/datalog_functional_relation.mbt` | Use `self.rt.core.in_fixpoint` (2 occurrences) |
| `cells/pull_memo.mbt` | Remove `dirty : Bool` field from `MemoData` |
| `cells/hybrid_wbtest.mbt` | Remove `inspect(rt.pull.memos[h_idx].dirty, ...)` assertion |
| `tests/integration_test.mbt` | Add cross-engine regression test (datalog→push) — added in Task 1 |

---

## Task 1: Add `Runtime::publish_cell_changes` — the kernel notification protocol

This is a pure addition. It extracts the pattern that currently appears verbatim at the end of `Runtime::fixpoint` into a named kernel method. No behavior change yet.

**Files:**
- Modify: `cells/runtime.mbt` (add method)
- Modify: `tests/integration_test.mbt` (add regression test)

- [ ] **Step 1: Write a cross-engine regression test**

In `tests/integration_test.mbt`, add this test at the end of the file. It verifies that fixpoint advances the revision and fires `on_change` when facts change (and skips both when nothing changed). Run it first to confirm it passes — this captures the behavior we must preserve through the refactoring.

Note: `Reactive` is not exported from `dowdiness/incr`, so the test uses `Runtime::set_on_change` to observe that the notification path ran.

```moonbit
///|
test "cross-engine: fixpoint fires on_change only when facts change" {
  let rt = Runtime::new()
  let rel = Relation::new(rt, label="R")
  let mut notifications = 0
  rt.set_on_change(fn() { notifications = notifications + 1 })
  // Fixpoint with no pending delta — no notification expected
  rt.fixpoint()
  inspect(notifications, content="0")
  // Insert a fact so the delta is non-empty, then run fixpoint
  rel.insert(42)
  rt.fixpoint()
  inspect(notifications, content="1")
}
```

- [ ] **Step 2: Run test to confirm it passes**

```bash
moon test -p dowdiness/incr/tests -f integration_test.mbt
```
Expected: test passes (we're capturing existing behavior, not a new feature).

- [ ] **Step 3: Add `publish_cell_changes` to `cells/runtime.mbt`**

Add this method after `Runtime::fire_on_change` (around line 385):

```moonbit
///|
/// Advances the global revision, marks cells as changed, triggers push
/// propagation (if any push cells exist), and fires the on_change callback.
///
/// This is the **kernel notification protocol** — the single method that
/// cross-engine code calls when a set of cells has new values. Engines
/// must not call `push_propagate_from` or `advance_revision` directly;
/// they call this instead.
///
/// # Parameters
///
/// - `changed_ids`: The cell IDs whose values changed
/// - `durability`: Durability level of the change (affects shortcut skipping)
fn Runtime::publish_cell_changes(
  self : Runtime,
  changed_ids : Array[CellId],
  durability : Durability,
) -> Unit {
  self.advance_revision(durability)
  for id in changed_ids {
    self.core.cell_ops[id.id].set_changed_at(self.core.current_revision)
  }
  if self.push.node_count > 0 {
    self.push_propagate_from(changed_ids)
  }
  self.fire_on_change()
}
```

- [ ] **Step 4: Run `moon check`**

```bash
moon check
```
Expected: 0 errors. (The method is unused so far — a warning is fine.)

- [ ] **Step 5: Commit**

```bash
git add cells/runtime.mbt tests/integration_test.mbt
git commit -m "feat: add Runtime::publish_cell_changes kernel notification protocol"
```

---

## Task 2: Route `Runtime::fixpoint` through `publish_cell_changes`

The datalog engine currently reaches into the push engine directly. This task removes that coupling: `datalog_fixpoint.mbt` calls `publish_cell_changes` (a kernel method) instead of `push_propagate_from` (a push-engine method).

**Files:**
- Modify: `cells/datalog_fixpoint.mbt:106-115`

- [ ] **Step 1: Replace the post-fixpoint block in `datalog_fixpoint.mbt`**

Current code (lines 106–115):

```moonbit
  if changed_ids.length() > 0 {
    self.advance_revision(Low)
    for id in changed_ids {
      self.core.cell_ops[id.id].set_changed_at(self.core.current_revision)
    }
    if self.push.node_count > 0 {
      self.push_propagate_from(changed_ids)
    }
    self.fire_on_change()
  }
```

Replace with:

```moonbit
  if changed_ids.length() > 0 {
    self.publish_cell_changes(changed_ids, Low)
  }
```

- [ ] **Step 2: Run all tests**

```bash
moon test
```
Expected: All tests pass (same count as before Task 1).

- [ ] **Step 3: Run `moon check`**

```bash
moon check
```
Expected: 0 errors, no new warnings.

- [ ] **Step 4: Commit**

```bash
git add cells/datalog_fixpoint.mbt
git commit -m "refactor: route fixpoint post-change notification through publish_cell_changes"
```

---

## Task 3: Move `in_fixpoint` from `DatalogState` to `RuntimeCore`

`pull_verify` currently reads `self.datalog.in_fixpoint` — the pull engine reading datalog engine state. Moving the flag to `RuntimeCore` makes it a kernel concern (it affects what all engines can do during fixpoint), removing the pull→datalog coupling.

**Files:**
- Modify: `cells/runtime.mbt` (add to `RuntimeCore`, remove from `DatalogState`)
- Modify: `cells/datalog_fixpoint.mbt` (3 occurrences)
- Modify: `cells/verify.mbt` (2 occurrences)
- Modify: `cells/memo.mbt` (1 occurrence)
- Modify: `cells/hybrid_memo.mbt` (1 occurrence)
- Modify: `cells/datalog_relation.mbt` (1 occurrence)
- Modify: `cells/datalog_functional_relation.mbt` (2 occurrences)

- [ ] **Step 1: Update `RuntimeCore` in `cells/runtime.mbt`**

Add `mut in_fixpoint : Bool` to `RuntimeCore` after the `cell_ops` field (around line 54):

```moonbit
priv struct RuntimeCore {
  runtime_id : Int
  mut current_revision : Revision
  mut next_cell_id : Int
  tracking_stack : Array[ActiveQuery]
  durability_last_changed : FixedArray[Revision]
  mut batch_depth : Int
  batch_pending : Array[&Committable]
  batch_frames : Array[BatchFrame]
  mut batch_max_durability : Durability
  mut on_change : (() -> Unit)?
  cell_index : Array[CellRef]
  cell_ops : Array[&CellOps]
  /// True while Runtime::fixpoint() is running. Cross-engine guard: prevents
  /// pull_verify, Memo::get(), HybridMemo::get(), and Relation::insert()
  /// from running concurrently with semi-naive delta tracking.
  mut in_fixpoint : Bool
}
```

Remove `mut in_fixpoint : Bool` from `DatalogState` (lines 80–85 become):

```moonbit
priv struct DatalogState {
  relations : Array[RelationData]
  functional_relations : Array[FunctionalRelationData]
  rules : Array[RuleData]
}
```

In `Runtime::new`, add `in_fixpoint: false` to the `core` initializer block and remove `in_fixpoint: false` from the `datalog` initializer block:

```moonbit
// In core: { initializer block }
core: {
  runtime_id: id,
  current_revision: Revision::initial(),
  next_cell_id: 0,
  tracking_stack: [],
  durability_last_changed: FixedArray::make(
    @incr_types.DURABILITY_COUNT,
    Revision::initial(),
  ),
  batch_depth: 0,
  batch_pending: [],
  batch_frames: [],
  batch_max_durability: Low,
  on_change,
  cell_index: [],
  cell_ops: [],
  in_fixpoint: false,    // <-- add here
},
// ...
datalog: {
  relations: [],
  functional_relations: [],
  rules: [],
  // (in_fixpoint removed)
},
```

- [ ] **Step 2: Run `moon check` to find all remaining compiler errors**

```bash
moon check
```
Expected: Several errors pointing to `self.datalog.in_fixpoint` usages. Use the error list to find each file.

- [ ] **Step 3: Update `cells/datalog_fixpoint.mbt`**

Replace all 3 occurrences of `self.datalog.in_fixpoint` with `self.core.in_fixpoint`:

Line 13: `if self.datalog.in_fixpoint {` → `if self.core.in_fixpoint {`

Line 30: `self.datalog.in_fixpoint = true` → `self.core.in_fixpoint = true`

Line 89: `self.datalog.in_fixpoint = false` → `self.core.in_fixpoint = false`

- [ ] **Step 4: Update `cells/verify.mbt`**

Line 84: `if self.datalog.in_fixpoint {` → `if self.core.in_fixpoint {`

Line 128: `if self.datalog.in_fixpoint {` → `if self.core.in_fixpoint {`

- [ ] **Step 5: Update `cells/memo.mbt`**

Line 159: `if self.rt.datalog.in_fixpoint {` → `if self.rt.core.in_fixpoint {`

- [ ] **Step 6: Update `cells/hybrid_memo.mbt`**

Line 79: `if self.rt.datalog.in_fixpoint {` → `if self.rt.core.in_fixpoint {`

- [ ] **Step 7: Update `cells/datalog_relation.mbt`**

Line 98: `if self.rt.datalog.in_fixpoint {` → `if self.rt.core.in_fixpoint {`

- [ ] **Step 8: Update `cells/datalog_functional_relation.mbt`**

Line 100: `if self.rt.datalog.in_fixpoint {` → `if self.rt.core.in_fixpoint {`

Line 147: `if self.rt.datalog.in_fixpoint {` → `if self.rt.core.in_fixpoint {`

- [ ] **Step 9: Run `moon check`**

```bash
moon check
```
Expected: 0 errors.

- [ ] **Step 10: Run all tests**

```bash
moon test
```
Expected: All tests pass (same count as after Task 2).

- [ ] **Step 11: Commit**

```bash
git add cells/runtime.mbt cells/datalog_fixpoint.mbt cells/verify.mbt cells/memo.mbt cells/hybrid_memo.mbt cells/datalog_relation.mbt cells/datalog_functional_relation.mbt
git commit -m "refactor: move in_fixpoint from DatalogState to RuntimeCore"
```

---

## Task 4: Remove the dead `dirty` field from `MemoData`

The `dirty` field on `MemoData` is never set to `true` — only `PushReactiveData` and `PushEffectData` use `dirty = true`. The HybridMemo dirty-marking approach that would have used this field was superseded by `verified_at` staleness detection (see `docs/archive/completed-phases/2026-03-08-hybrid-dirty-separation.md`). All reads of `not(cell.dirty) &&` are vacuously true and all writes of `cell.dirty = false` are no-ops.

Removing this field makes `MemoData` a pure pull-mode type and eliminates confusion about why hybrid semantics appear in a pull-mode struct.

**Files:**
- Modify: `cells/pull_memo.mbt` (remove `dirty` field)
- Modify: `cells/verify.mbt` (remove 3 guards + 1 assignment)
- Modify: `cells/memo.mbt` (remove 1 assignment)
- Modify: `cells/hybrid_memo.mbt` (remove 2 guards + 1 assignment)
- Modify: `cells/hybrid_wbtest.mbt` (remove 1 assertion)

- [ ] **Step 1: Remove `dirty : Bool` from `MemoData` in `cells/pull_memo.mbt`**

Current struct (lines 7–15):
```moonbit
priv struct MemoData {
  meta : CellMeta
  compute : () -> Result[Bool, CycleError]
  mut verified_at : Revision
  mut dependencies : Array[CellId]
  mut in_progress : Bool
  mut dirty : Bool
  mut on_change : (() -> Unit)?
}
```

Remove `mut dirty : Bool`:
```moonbit
priv struct MemoData {
  meta : CellMeta
  compute : () -> Result[Bool, CycleError]
  mut verified_at : Revision
  mut dependencies : Array[CellId]
  mut in_progress : Bool
  mut on_change : (() -> Unit)?
}
```

- [ ] **Step 2: Run `moon check` to surface all remaining usages**

```bash
moon check
```
Expected: Errors for every remaining reference to `.dirty` on a `MemoData` value. Use the list to find each one.

- [ ] **Step 3: Remove dead `dirty` guards from `cells/verify.mbt`**

Three changes:

Line 92 — remove `not(root.dirty) &&`:
```moonbit
// Before:
      if not(root.dirty) && root.verified_at >= self.core.current_revision {
// After:
      if root.verified_at >= self.core.current_revision {
```

Lines 97–99 — remove `not(root.dirty) &&`:
```moonbit
// Before:
      if not(root.dirty) &&
        self.core.durability_last_changed[root.meta.durability.index()] <=
        root.verified_at {
// After:
      if self.core.durability_last_changed[root.meta.durability.index()] <=
        root.verified_at {
```

Lines 152–153 — remove `not(dep.dirty) &&`:
```moonbit
// Before:
                    if not(dep.dirty) &&
                      self.core.durability_last_changed[dep.meta.durability.index()] <=
                      dep.verified_at {
// After:
                    if self.core.durability_last_changed[dep.meta.durability.index()] <=
                      dep.verified_at {
```

Line 205 — remove `memo.dirty = false`:
```moonbit
// Before:
          memo.dirty = false
          // Tell the parent frame...
// After:
          // Tell the parent frame...
```

- [ ] **Step 4: Remove `cell.dirty = false` from `cells/memo.mbt`**

Line 360 — remove `cell.dirty = false`:
```moonbit
// Before (lines 359–361):
  cell.verified_at = self.core.current_revision
  cell.dirty = false
  cell.in_progress = false
// After:
  cell.verified_at = self.core.current_revision
  cell.in_progress = false
```

- [ ] **Step 5: Remove `dirty` checks from `cells/hybrid_memo.mbt`**

Line 96 — remove `not(cell.dirty) &&`:
```moonbit
// Before:
      if not(cell.dirty) && cell.verified_at >= self.rt.core.current_revision {
// After:
      if cell.verified_at >= self.rt.core.current_revision {
```

Line 103 — remove `cell.dirty = false`:
```moonbit
// Before:
          cell.dirty = false
          self.rt.record_dependency(self.cell_id)
// After:
          self.rt.record_dependency(self.cell_id)
```

- [ ] **Step 6: Remove `dirty: false` from struct initializers in `cells/memo.mbt` and `cells/hybrid_memo.mbt`**

`Memo::new` (line 84) initializes `dirty: false` when pushing to `rt.pull.memos`. Remove that field from the initializer:

```moonbit
// cells/memo.mbt — in Memo::new, the rt.pull.memos.push({ ... }) block
// Before:
    in_progress: false,
    dirty: false,
    on_change: None,
// After:
    in_progress: false,
    on_change: None,
```

`HybridMemo::new` (line 50) does the same. Remove it:

```moonbit
// cells/hybrid_memo.mbt — in HybridMemo::new, the rt.pull.memos.push({ ... }) block
// Before:
    in_progress: false,
    dirty: false,
    on_change: None,
// After:
    in_progress: false,
    on_change: None,
```

- [ ] **Step 7: Remove stale assertion from `cells/hybrid_wbtest.mbt`**

Find and remove the line:
```moonbit
  inspect(rt.pull.memos[h_idx].dirty, content="false")
```

- [ ] **Step 8: Run `moon check`**

```bash
moon check
```
Expected: 0 errors.

- [ ] **Step 9: Run all tests**

```bash
moon test
```
Expected: All tests pass. Count should be one fewer (the `dirty` whitebox assertion removed in Step 6), but total pass count stays the same since the test still runs — only one `inspect` call is removed from it.

- [ ] **Step 10: Update interfaces and format**

```bash
moon info && moon fmt
```
Expected: `.mbti` files updated (MemoData lost one field). Review the diff:

```bash
git diff *.mbti
```
`MemoData` should no longer expose `dirty`. If other `.mbti` changes appear, review them to ensure they're intentional.

- [ ] **Step 11: Commit**

```bash
git add cells/pull_memo.mbt cells/verify.mbt cells/memo.mbt cells/hybrid_memo.mbt cells/hybrid_wbtest.mbt
git commit -m "refactor: remove dead dirty field from MemoData"
```

---

## Final Verification

- [ ] **Run full test suite**

```bash
moon test
```
Expected: All tests pass.

- [ ] **Run benchmarks to confirm no regression**

```bash
moon bench --release
```
Check `memo: get stale` and `hybrid: get stale` — should be unchanged or slightly faster (fewer branches in verify).

- [ ] **Update docs/README.md** — add this plan to the Archive index once the tasks are done

```bash
git mv docs/superpowers/plans/2026-03-24-kernel-mode-engines.md docs/archive/completed-phases/2026-03-24-kernel-mode-engines.md
```
Then update `docs/README.md` to list it under Archive.
