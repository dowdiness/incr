# Coordinator Routing Implementation Plan

**Status:** Complete — shipped. `Runtime::propagate_changes` exists in `cells/runtime.mbt`; `publish_cell_changes` delegates to it; `commit_batch` (`cells/batch.mbt`) and `signal.set_unconditional` (`cells/signal.mbt`) route through it; `mark_input_changed` was deleted as planned. Plan line numbers below are stale relative to current `runtime.mbt` and are preserved for historical accuracy.

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Route all push propagation through a single coordinator method (`propagate_changes`), eliminating direct `push_propagate_from` calls from batch, signal, and fixpoint code.

**Architecture:** Extract `Runtime::propagate_changes` as the core coordinator method (advance revision + stamp changed_at + push propagate). Migrate `publish_cell_changes`, `commit_batch`, and `signal.set_unconditional` to use it. Delete `mark_input_changed` (dead after migration). Preserve the callback-snapshot-before-propagation invariant.

**Tech Stack:** MoonBit, moon check/test/fmt/info

**Spec:** `docs/design/specs/2026-04-16-runtime-modularization-phase2-design.md` (PR 1 section)

---

## File Structure

All changes are internal to `cells/`. No public API changes. No new files.

**Modified files:**

| File | Changes |
|------|---------|
| `cells/runtime.mbt` | Add `propagate_changes`; rewrite `publish_cell_changes`; delete `mark_input_changed`; update doc comment |
| `cells/batch.mbt` | Rewrite `commit_batch` Phase 2 to use `propagate_changes` |
| `cells/signal.mbt` | Rewrite `set_unconditional` non-batched path to use `propagate_changes` |
| `cells/cell_ops.mbt` | Update stale comment referencing `mark_input_changed` |

---

## Task 1: Add `propagate_changes` and Rewrite `publish_cell_changes`

**Files:**
- Modify: `cells/runtime.mbt:595-627`

- [ ] **Step 1: Add `propagate_changes` method**

Add immediately before the current `publish_cell_changes` function (before line 595 in `cells/runtime.mbt`):

```moonbit
///|
/// Core propagation coordinator: advances the revision, stamps changed_at on
/// all changed cells, and runs push propagation if any push cells exist.
///
/// This is the single entry point for push propagation. All paths that notify
/// the runtime of cell value changes call this method. Callers handle their
/// own callback sequencing around it:
///
/// - `publish_cell_changes`: adds `fire_on_change()` (simple path for fixpoint)
/// - `commit_batch`: snapshots per-signal callbacks before, fires after
/// - `signal.set_unconditional`: snapshots per-signal callback before, fires after
fn Runtime::propagate_changes(
  self : Runtime,
  changed_ids : Array[CellId],
  durability : Durability,
) -> Unit {
  self.advance_revision(durability)
  for id in changed_ids {
    self.core.cell_ops[id.id].set_changed_at(
      self.core.revision.current_revision,
    )
  }
  if self.push.node_count > 0 {
    self.push_propagate_from(changed_ids)
  }
}
```

- [ ] **Step 2: Rewrite `publish_cell_changes` to use `propagate_changes`**

Replace the entire `publish_cell_changes` function and its doc comment (lines 595-627) with:

```moonbit
///|
/// Kernel notification protocol: notifies the runtime that a set of cells
/// has new values.
///
/// Delegates to `propagate_changes` for revision bump, changed_at stamping,
/// and push propagation, then fires the global `on_change` callback.
///
/// Use this for callers that don't need custom callback sequencing (e.g.
/// `fixpoint`). Callers that interleave per-cell callbacks with propagation
/// (e.g. `commit_batch`, `signal.set_unconditional`) call `propagate_changes`
/// directly and manage their own callback timing.
///
/// # Parameters
///
/// - `changed_ids`: The cell IDs whose values changed
/// - `durability`: Durability level of the change
fn Runtime::publish_cell_changes(
  self : Runtime,
  changed_ids : Array[CellId],
  durability : Durability,
) -> Unit {
  self.propagate_changes(changed_ids, durability)
  self.fire_on_change()
}
```

- [ ] **Step 3: Run moon check**

Run: `moon check 2>&1`
Expected: PASS — `mark_input_changed` still exists and its callers still use it. Only `publish_cell_changes` changed.

- [ ] **Step 4: Run moon test**

Run: `moon test 2>&1`
Expected: All tests pass (including `runtime_wbtest.mbt` which exercises `publish_cell_changes`)

- [ ] **Step 5: Commit**

```bash
git add cells/runtime.mbt
git commit -m "refactor: add propagate_changes coordinator, rewrite publish_cell_changes to use it"
```

---

## Task 2: Migrate `commit_batch` and `signal.set_unconditional`

These two migrations are done together in one commit because `mark_input_changed` must be deleted only after both callers are migrated — each intermediate state would break compilation.

**Files:**
- Modify: `cells/batch.mbt:161-181`
- Modify: `cells/signal.mbt:218-232`
- Modify: `cells/runtime.mbt` (delete `mark_input_changed`)

- [ ] **Step 1: Replace the Phase 2 body in `commit_batch`**

In `cells/batch.mbt`, replace lines 161-181 (the `if changed.length() > 0` body, from `any_changed = true` through `self.core.batch.max_durability = Low` before the callback block):

Current code:

```moonbit
      any_changed = true
      self.advance_revision(self.core.batch.max_durability)
      // Sweep changed signals: update changed_at and snapshot on_change callbacks.
      // Handlers are captured here — before any callback executes — so that a
      // callback calling clear_on_change() or on_change() on another changed signal
      // cannot affect which handlers fire in this batch wave.
      let callbacks : Array[() -> Unit] = []
      for c in changed {
        let sig = self.mark_input_changed(c.cell_id())
        match sig.on_change {
          Some(f) => callbacks.push(f)
          None => ()
        }
      }
      // Push propagation must run before per-signal callbacks so callback
      // reads observe fully-updated push-reactive state for this wave.
      if self.push.node_count > 0 {
        let changed_ids : Array[CellId] = changed.map(c => c.cell_id())
        self.push_propagate_from(changed_ids)
      }
      self.core.batch.max_durability = Low
```

Replace with:

```moonbit
      any_changed = true
      // Snapshot on_change callbacks BEFORE propagation — preserves the
      // invariant that push propagation cannot affect which handlers fire
      // in this batch wave (a PushReactive's compute closure could call
      // clear_on_change() or on_change() on a changed signal).
      let callbacks : Array[() -> Unit] = []
      for c in changed {
        let sig = self.get_pull_signal(c.cell_id())
        match sig.on_change {
          Some(f) => callbacks.push(f)
          None => ()
        }
      }
      let changed_ids : Array[CellId] = changed.map(fn(c) { c.cell_id() })
      self.propagate_changes(changed_ids, self.core.batch.max_durability)
      self.core.batch.max_durability = Low
```

The rest of the function (batch_depth raise, callback firing, else branch, while loop, trailing max_durability reset, fire_on_change) stays unchanged.

- [ ] **Step 2: Replace the non-batched path in `signal.set_unconditional`**

In `cells/signal.mbt`, replace lines 218-232 (the `else` branch of the batch_depth check):

Current code:

```moonbit
  } else {
    self.value = new_value
    self.rt.bump_revision(self.durability)
    let sig = self.rt.mark_input_changed(self.cell_id)
    // Push propagation must run before per-signal callbacks so callback reads
    // cannot observe stale push-reactive state in the current revision.
    if self.rt.push.node_count > 0 {
      self.rt.push_propagate_from([self.cell_id])
    }
    match sig.on_change {
      Some(f) => f()
      None => ()
    }
    self.rt.fire_on_change()
  }
```

Replace with:

```moonbit
  } else {
    self.value = new_value
    // Snapshot callback before propagation — same invariant as commit_batch:
    // push propagation must not affect which handler fires.
    let cb = self.rt.get_pull_signal(self.cell_id).on_change
    self.rt.propagate_changes([self.cell_id], self.durability)
    match cb {
      Some(f) => f()
      None => ()
    }
    self.rt.fire_on_change()
  }
```

Note: `bump_revision` is removed because `propagate_changes` calls `advance_revision` directly. This path is only entered when `batch_depth == 0`, at which point `bump_revision` would fall through to `advance_revision` anyway — semantically equivalent.

- [ ] **Step 3: Delete `mark_input_changed` from runtime.mbt**

Delete the function and its doc comment (currently around lines 643-651 after Task 1's edits — find by searching for `fn Runtime::mark_input_changed`):

```moonbit
///|
/// Mark an input cell as changed at the current revision.
/// Sets changed_at to current_revision on the PullSignalData entry.
/// Must be called after advance_revision so current_revision is already updated.
fn Runtime::mark_input_changed(self : Runtime, id : CellId) -> PullSignalData {
  let sig = self.get_pull_signal(id)
  sig.meta.changed_at = self.core.revision.current_revision
  sig
}
```

- [ ] **Step 4: Run moon check**

Run: `moon check 2>&1`
Expected: PASS — all three call sites migrated, definition deleted.

- [ ] **Step 5: Run callback tests**

Run: `moon test -p dowdiness/incr/cells -f callback_test.mbt 2>&1`
Expected: All 11 callback tests pass, including:
- `"batch: callback sees fresh push-reactive state before memo read"` — verifies push propagation completes before callbacks
- `"batch: per-cell callbacks fire once per changed signal"` — verifies callback collection
- `"batch: global on_change fires exactly once when callback sets another signal"` — verifies multi-wave loop
- `"signal callback sees fresh push-reactive state before memo read"` — verifies non-batched push-then-callback ordering
- `"non-batch: callback re-entrancy — set inside on_change propagates and memo reads correctly"` — verifies recursive set_unconditional

- [ ] **Step 6: Run full test suite**

Run: `moon test 2>&1`
Expected: All 508+ tests pass

- [ ] **Step 7: Commit**

```bash
git add cells/runtime.mbt cells/batch.mbt cells/signal.mbt
git commit -m "refactor: migrate commit_batch and signal.set_unconditional to propagate_changes, delete mark_input_changed"
```

---

## Task 3: Update Stale Comment in `cell_ops.mbt`

**Files:**
- Modify: `cells/cell_ops.mbt:65-67`

- [ ] **Step 1: Update the `set_changed_at` doc comment**

In `cells/cell_ops.mbt`, replace lines 65-67:

Current:

```moonbit
  /// Stamps `changed_at` to `rev`. Used by Phase 3 cell kinds that need a
  /// generic write path; current pull-cell internals write the field directly
  /// (see `mark_input_changed`, `force_recompute`).
```

Replace with:

```moonbit
  /// Stamps `changed_at` to `rev`. Used by `propagate_changes` to stamp all
  /// changed cells generically, and by cell kinds that need a direct write path
  /// (see `force_recompute`).
```

- [ ] **Step 2: Commit**

```bash
git add cells/cell_ops.mbt
git commit -m "docs: update stale comment referencing deleted mark_input_changed"
```

---

## Task 4: Final Verification and Cleanup

**Files:**
- No code modifications — verification and formatting only

- [ ] **Step 1: Verify `push_propagate_from` has exactly one caller**

Run: `grep -rn 'push_propagate_from' cells/*.mbt | grep -v '_test\|_wbtest\|_bench\|//'`
Expected: Exactly two results:
1. `cells/runtime.mbt` — the call inside `propagate_changes`
2. `cells/push_propagate.mbt` — the function definition

- [ ] **Step 2: Verify `mark_input_changed` is fully removed**

Run: `grep -rn 'mark_input_changed' cells/*.mbt`
Expected: Zero results (no references remain)

- [ ] **Step 3: Run integration tests**

Run: `moon test -p dowdiness/incr/tests 2>&1`
Expected: All integration tests pass

- [ ] **Step 4: Verify the publish_cell_changes whitebox test still passes**

Run: `moon test -p dowdiness/incr/cells -f runtime_wbtest.mbt 2>&1`
Expected: `"publish_cell_changes: advances revision, marks changed_at, fires on_change"` passes — this exercises the full `publish_cell_changes` → `propagate_changes` chain.

- [ ] **Step 5: Run moon fmt and moon info**

Run: `moon info && moon fmt 2>&1`
Expected: No errors

- [ ] **Step 6: Check .mbti for unintended API changes**

Run: `git diff *.mbti`
Expected: No changes (all modifications are to `priv`/`fn` internals)

- [ ] **Step 7: Commit any formatting changes**

```bash
git diff --stat  # verify only expected files
git add -A
git commit -m "chore: run moon fmt and moon info after coordinator routing"
```
