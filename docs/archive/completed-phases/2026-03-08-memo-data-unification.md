# MemoData Unification Implementation Plan

> **For Claude:** REQUIRED SUB-SKILL: Use superpowers:executing-plans to implement this plan task-by-task.

**Status:** Complete

**Goal:** Merge `PullMemoData` and `HybridMemoData` into a single `MemoData` struct to eliminate ~200 lines of cascading duplication across SoA definitions, CellOps impls, accessor methods, verify functions, and force_recompute methods.

**Architecture:** Both structs share 9 of 11 fields. The only differences are `on_change` (pull-only) and `dirty` (hybrid-only). Adding one unused `Bool` per pull memo and one unused `Option` per hybrid memo is negligible. With a single SoA type, `CellRef` keeps both `PullMemo(Int)` and `HybridMemo(Int)` variants pointing into the same `memos` array — push propagation still knows which memos to dirty. The verify functions and force_recompute methods then operate on the same data type, enabling unification.

**Tech Stack:** MoonBit, moon CLI (check/test/info/fmt)

---

## Dependency Graph

```
Task 1 (MemoData struct)
  ↓
Task 2 (CellOps impls)
  ↓
Task 3 (Runtime storage + accessors)
  ↓
Task 4 (Memo::new + HybridMemo::new constructors)
  ↓
Task 5 (force_recompute unification)
  ↓
Task 6 (verify unification)
  ↓
Task 7 (Update whitebox tests)
  ↓
Task 8 (Cleanup + docs)
```

Tasks 1–4 are mechanical renames. Tasks 5–6 are the substantive logic changes. Task 7 updates tests that access internal fields. Task 8 is cleanup.

---

### Task 1: Define `MemoData` struct, replacing both `PullMemoData` and `HybridMemoData`

**Files:**
- Modify: `cells/pull_memo.mbt` (rename struct, add `dirty` field)
- Modify: `cells/hybrid_memo.mbt` (remove `HybridMemoData` struct definition)

**Step 1: Rename `PullMemoData` to `MemoData` and add the two missing fields**

In `cells/pull_memo.mbt`, replace the struct definition:

```moonbit
///|
/// Type-erased metadata for all memo cells (pull and hybrid) in the SoA layout.
///
/// The actual typed value lives in the `Memo[T]` or `HybridMemo[T]` handle
/// held by user code. `compute` is a closure captured at construction time
/// that recomputes the memo and returns whether the value changed.
///
/// Pull memos use `dirty = false` (never set) and `on_change` for callbacks.
/// Hybrid memos use `dirty` for push-propagated invalidation and `on_change = None`.
priv struct MemoData {
  cell_id : CellId
  label : String?
  compute : () -> Result[Bool, CycleError]
  mut changed_at : Revision
  mut verified_at : Revision
  mut durability : Durability
  mut dependencies : Array[CellId]
  subscribers : @hashset.HashSet[CellId]
  mut in_progress : Bool
  mut on_change : (() -> Unit)?   // Pull memos only; None for hybrid memos
  mut dirty : Bool                // Hybrid memos only; always false for pull memos
}
```

**Step 2: Remove `HybridMemoData` struct from `cells/hybrid_memo.mbt`**

Delete the `priv struct HybridMemoData { ... }` block (lines 7–18).

**Step 3: Run `moon check`**

Expected: Many errors — `PullMemoData` and `HybridMemoData` are referenced everywhere. This confirms the rename propagates. Do NOT fix them yet.

**Step 4: Commit**

```bash
git add cells/pull_memo.mbt cells/hybrid_memo.mbt
git commit -m "refactor: define unified MemoData struct (compile errors expected)"
```

---

### Task 2: Unify CellOps implementations

**Files:**
- Modify: `cells/pull_memo.mbt` (rename impls from `PullMemoData` to `MemoData`)
- Modify: `cells/hybrid_memo.mbt` (remove duplicate CellOps impls)

**Step 1: In `cells/pull_memo.mbt`, rename all `impl CellOps for PullMemoData` to `impl CellOps for MemoData`**

There are 7 impl blocks to rename. The `dep_changed_since` override stays:

```moonbit
///|
impl CellOps for MemoData with dep_changed_since(_self, _verified_at) -> Bool? {
  None
}
```

**Step 2: In `cells/hybrid_memo.mbt`, delete all `impl CellOps for HybridMemoData` blocks**

Remove the 7 impl blocks (lines 21–23 and lines 219–248). They are now redundant — `MemoData` already has the impls.

**Step 3: Run `moon check`**

Expected: Fewer errors — CellOps is resolved, but storage and accessor references still broken.

**Step 4: Commit**

```bash
git add cells/pull_memo.mbt cells/hybrid_memo.mbt
git commit -m "refactor: unify CellOps impls under MemoData"
```

---

### Task 3: Unify Runtime storage and accessor methods

**Files:**
- Modify: `cells/runtime.mbt`

**Step 1: Replace `PullState.memos` type and move hybrid memos into it**

In `cells/runtime.mbt`, change `PullState`:

```moonbit
///|
/// Pull-mode SoA storage (lazy verification).
priv struct PullState {
  signals : Array[PullSignalData]
  memos : Array[MemoData]          // ← was Array[PullMemoData]; now stores both pull and hybrid memos
}
```

Remove `hybrid_memos` from `PushState`:

```moonbit
///|
/// Push-mode SoA storage (eager propagation).
priv struct PushState {
  reactives : Array[PushReactiveData]
  effects : Array[PushEffectData]
  free_reactives : Array[Int]
  free_effects : Array[Int]
  mut node_count : Int
  // hybrid_memos removed — now in PullState.memos
  hybrid_dirty : Array[CellId]
}
```

**Step 2: Update `Runtime::new` constructor**

Remove `hybrid_memos: []` from the `push` initializer. The `pull.memos` field already covers both.

**Step 3: Replace `get_pull_memo` and `get_hybrid_memo` with a single `get_memo_data`**

Replace both methods with:

```moonbit
///|
/// Returns the MemoData for any memo cell (pull or hybrid).
///
/// # Panics
///
/// Aborts if the cell belongs to a different runtime or is not a memo.
fn Runtime::get_memo_data(self : Runtime, id : CellId) -> MemoData {
  self.validate_cell(id, "get_memo_data")
  match self.core.cell_index[id.id] {
    PullMemo(idx) | HybridMemo(idx) => self.pull.memos[idx]
    _ =>
      abort(
        "Expected memo cell but found different kind: " + id.id.to_string(),
      )
  }
}
```

**Step 4: Update `cell_id_for` — both variants now index `pull.memos`**

```moonbit
    PullMemo(idx) => self.pull.memos[idx].cell_id
    HybridMemo(idx) => self.pull.memos[idx].cell_id
```

Or use the combined pattern:

```moonbit
    PullMemo(idx) | HybridMemo(idx) => self.pull.memos[idx].cell_id
```

**Step 5: Run `moon check`**

Expected: Errors in callers of `get_pull_memo` / `get_hybrid_memo` and `push.hybrid_memos`. These are fixed in subsequent tasks.

**Step 6: Commit**

```bash
git add cells/runtime.mbt
git commit -m "refactor: unify memo SoA storage and accessor into MemoData"
```

---

### Task 4: Update constructors — `Memo::new` and `HybridMemo::new`

**Files:**
- Modify: `cells/memo.mbt` (update `Memo::new` to use `MemoData`)
- Modify: `cells/hybrid_memo.mbt` (update `HybridMemo::new` to push into `pull.memos`)

**Step 1: In `cells/memo.mbt`, update `Memo::new`**

Change `rt.pull.memos.push({...})` to include the new `dirty` field:

```moonbit
  rt.pull.memos.push({
    cell_id,
    label,
    compute: () => memo.recompute_inner(),
    changed_at: Revision::initial(),
    verified_at: Revision::initial(),
    durability: Low,
    dependencies: [],
    subscribers: @hashset.new(),
    in_progress: false,
    on_change: None,
    dirty: false,           // ← new field, always false for pull memos
  })
```

**Step 2: In `cells/hybrid_memo.mbt`, update `HybridMemo::new`**

Change from `rt.push.hybrid_memos` to `rt.pull.memos`:

```moonbit
  let memo_idx = rt.pull.memos.length()               // ← was rt.push.hybrid_memos
  let cell_id = rt.alloc_cell_id(HybridMemo(memo_idx))
  let memo : HybridMemo[T] = { label, rt, cell_id, compute, value: None }
  rt.pull.memos.push({                                  // ← was rt.push.hybrid_memos
    cell_id,
    label,
    compute: () => memo.recompute_inner(),
    changed_at: Revision::initial(),
    verified_at: Revision::initial(),
    durability: Low,
    dependencies: [],
    subscribers: @hashset.new(),
    in_progress: false,
    on_change: None,          // ← new field, None for hybrid memos
    dirty: false,
  })
  let ops : &CellOps = rt.pull.memos[memo_idx]         // ← was rt.push.hybrid_memos
  rt.core.cell_ops.push(ops)
  rt.push.node_count = rt.push.node_count + 1
  memo
```

**Step 3: Rename all `get_pull_memo` calls to `get_memo_data` in `cells/memo.mbt`**

There are 8 call sites in memo.mbt (lines 175, 238, 306, 373, 386, 399, 416, 427, 438). Replace all:

```
self.rt.get_pull_memo(self.cell_id)  →  self.rt.get_memo_data(self.cell_id)
```

**Step 4: Rename all `get_hybrid_memo` calls to `get_memo_data` in `cells/hybrid_memo.mbt`**

There are 4 call sites (lines 106, 143, 154, 209). Replace all:

```
self.rt.get_hybrid_memo(self.cell_id)  →  self.rt.get_memo_data(self.cell_id)
```

**Step 5: Update `cells/push_propagate.mbt` — hybrid dirty flag access**

Change `self.push.hybrid_memos[i]` references to `self.pull.memos[i]`:

In `enqueue_push_subscribers` (around line 161):
```moonbit
          HybridMemo(i) => {
            if not(self.pull.memos[i].dirty) {        // ← was self.push.hybrid_memos[i]
              self.pull.memos[i].dirty = true          // ← was self.push.hybrid_memos[i]
              self.push.hybrid_dirty.push(sub_id)
            }
            bfs_worklist.push(sub_id)
          }
```

**Step 6: Update `cells/introspection.mbt` — `cell_info` and `collect_in_progress_path`**

In `cell_info` (around line 105), the `PullMemo(idx)` branch already uses `self.pull.memos[idx]`. Add the `HybridMemo` variant to the same match arm:

```moonbit
    PullMemo(idx) | HybridMemo(idx) => {
      let memo = self.pull.memos[idx]
      Some(CellInfo::{
        label: ops.label(),
        id,
        changed_at: ops.changed_at(),
        verified_at: memo.verified_at,
        durability: ops.durability(),
        dependencies: memo.dependencies.copy(),
        subscribers: snapshot_subscribers(ops.subscribers()),
      })
    }
```

In `collect_in_progress_path` (around line 154), remove the separate `push.hybrid_memos` loop since both are now in `pull.memos`:

```moonbit
fn Runtime::collect_in_progress_path(self : Runtime) -> Array[CellId] {
  let path : Array[CellId] = []
  for memo in self.pull.memos {
    if memo.in_progress {
      path.push(memo.cell_id)
    }
  }
  path
}
```

**Step 7: Run `moon check`**

Expected: Should compile. If errors remain, they'll be in whitebox tests (Task 7).

**Step 8: Run `moon test`**

Expected: All tests pass. If whitebox tests fail (they access `push.hybrid_memos` directly), they're fixed in Task 7.

**Step 9: Commit**

```bash
git add cells/memo.mbt cells/hybrid_memo.mbt cells/push_propagate.mbt cells/introspection.mbt
git commit -m "refactor: wire Memo and HybridMemo constructors to unified MemoData"
```

---

### Task 5: Unify `force_recompute` and `recompute_inner`

**Files:**
- Modify: `cells/memo.mbt`
- Modify: `cells/hybrid_memo.mbt`

Both `Memo::force_recompute` and `HybridMemo::force_recompute` are ~60 lines with 2 lines of difference. Since both now operate on `MemoData`, extract a shared helper on Runtime and have both typed handles call it.

**Step 1: Extract `Runtime::memo_force_recompute` in `cells/memo.mbt`**

Add below `compute_durability`:

```moonbit
///|
/// Shared force-recompute logic for all memo types (pull and hybrid).
///
/// Pushes a tracking frame, executes `compute_fn`, pops the frame,
/// diffs dependencies, maintains subscriber links, and handles backdating.
/// The `dirty` flag is always cleared (no-op for pull memos).
///
/// # Parameters
///
/// - `cell_id`: The memo's CellId
/// - `compute_fn`: The typed compute function that returns the new value
/// - `old_value`: The previous cached value (None if first computation)
/// - `eq_fn`: Equality check for backdating (compares old and new values)
///
/// # Returns
///
/// `Ok((new_value_changed, cell_changed_at_bumped))` on success,
/// `Err(CycleError)` if a cycle is detected.
///
/// `new_value_changed` is true if the new value differs from old_value.
/// `cell_changed_at_bumped` is true if changed_at was updated (not backdated).
fn[T] Runtime::memo_force_recompute(
  self : Runtime,
  cell_id : CellId,
  compute_fn : () -> T,
  old_value : T?,
  eq_fn : (T, T) -> Bool,
) -> Result[T, CycleError] {
  let cell = self.get_memo_data(cell_id)
  if cell.in_progress {
    return Err(
      CycleError::from_path(self.collect_tracking_path(), cell.cell_id),
    )
  }
  cell.in_progress = true
  let old_deps = cell.dependencies
  self.push_tracking(cell_id)
  let new_value = compute_fn()
  let (new_deps, new_seen) = self.pop_tracking()
  let mut deps_changed = new_deps.length() != old_deps.length()
  let old_seen : @hashset.HashSet[CellId] = @hashset.new()
  for dep in old_deps {
    old_seen.add(dep)
    if not(new_seen.contains(dep)) {
      deps_changed = true
    }
  }
  if deps_changed {
    for dep in old_deps {
      if not(new_seen.contains(dep)) {
        self.remove_subscriber(dep, cell_id)
      }
    }
    for dep in new_deps {
      if not(old_seen.contains(dep)) {
        self.add_subscriber(dep, cell_id)
      }
    }
  }
  cell.dependencies = new_deps
  if deps_changed {
    cell.durability = compute_durability(self, new_deps)
  }
  let value_changed = match old_value {
    None => true
    Some(old) => not(eq_fn(old, new_value))
  }
  if value_changed {
    cell.changed_at = self.core.current_revision
  }
  cell.verified_at = self.core.current_revision
  cell.dirty = false
  cell.in_progress = false
  Ok(new_value)
}
```

**Step 2: Simplify `Memo::force_recompute` to delegate**

```moonbit
///|
fn[T : Eq] Memo::force_recompute(self : Memo[T]) -> Result[T, CycleError] {
  match self.rt.memo_force_recompute(
    self.cell_id,
    self.compute,
    self.value,
    fn(a, b) { a == b },
  ) {
    Ok(new_value) => {
      self.value = Some(new_value)
      Ok(new_value)
    }
    Err(e) => Err(e)
  }
}
```

**Step 3: Simplify `HybridMemo::force_recompute` to delegate**

```moonbit
///|
fn[T : Eq] HybridMemo::force_recompute(
  self : HybridMemo[T],
) -> Result[T, CycleError] {
  match self.rt.memo_force_recompute(
    self.cell_id,
    self.compute,
    self.value,
    fn(a, b) { a == b },
  ) {
    Ok(new_value) => {
      self.value = Some(new_value)
      Ok(new_value)
    }
    Err(e) => Err(e)
  }
}
```

**Step 4: Verify `recompute_inner` still works**

`Memo::recompute_inner` and `HybridMemo::recompute_inner` both call `self.force_recompute()` — they don't need changes since force_recompute's return type and semantics are preserved. The only difference is `Memo::recompute_inner` fires `on_change`. This stays as-is:

```moonbit
// Memo::recompute_inner — fires on_change if changed_at bumped (unchanged)
// HybridMemo::recompute_inner — no on_change (unchanged)
```

**Step 5: Run `moon test`**

Expected: All tests pass.

**Step 6: Commit**

```bash
git add cells/memo.mbt cells/hybrid_memo.mbt
git commit -m "refactor: extract shared memo_force_recompute helper"
```

---

### Task 6: Unify verify functions

**Files:**
- Modify: `cells/verify.mbt`

Now that both `PullMemo` and `HybridMemo` index into the same `pull.memos` array, the verify functions can be merged.

**Step 1: Merge `pull_verify_hybrid` into `pull_verify`**

The key changes to `pull_verify`:

1. The root dispatch now handles `HybridMemo` the same as `PullMemo` (both go into the iterative stack):

```moonbit
    PullMemo(root_idx) | HybridMemo(root_idx) => {
```

2. The fast-path gate incorporates the dirty check (harmless for pull memos since `dirty` is always false):

```moonbit
      if not(root.dirty) && root.verified_at >= self.core.current_revision {
        return Ok(())
      }
      // Durability fast-path — also gated on not(dirty)
      if not(root.dirty) &&
        self.core.durability_last_changed[root.durability.index()] <=
        root.verified_at {
        root.verified_at = self.core.current_revision
        return Ok(())
      }
```

3. The inner loop's `None` branch for `HybridMemo` deps now pushes a frame instead of calling `pull_verify_hybrid`:

```moonbit
            None =>
              match self.core.cell_index[dep_id.id] {
                PullMemo(dep_idx) | HybridMemo(dep_idx) => {
                  let dep = self.pull.memos[dep_idx]
                  // ... same durability shortcut / cycle check / frame push logic
                }
                _ => ()
              }
```

4. The finalize block clears the dirty flag (no-op for pull memos):

```moonbit
          if frame_changed {
            match (memo.compute)() {
              Ok(_) => ()
              Err(e) => {
                clear_verify_stack(self, stack)
                return Err(e)
              }
            }
          }
          memo.verified_at = self.core.current_revision
          memo.dirty = false    // ← new: clears dirty for hybrid memos, no-op for pull
```

5. When propagating to parent frame, also check dirty (no-op for pull memo parents since dirty is false):

No change needed — the `changed_at > parent_memo.verified_at` check already works for both types.

**Step 2: Delete `pull_verify_hybrid`**

Remove the entire `Runtime::pull_verify_hybrid` function (lines 258–366).

**Step 3: Update callers of `pull_verify_hybrid`**

In `cells/hybrid_memo.mbt`, `HybridMemo::get` calls `self.rt.pull_verify_hybrid(self.cell_id)`. Change to `self.rt.pull_verify(self.cell_id)`:

```moonbit
      // Slow path: verify deps, then clear dirty flag
      match self.rt.pull_verify(self.cell_id) {    // ← was pull_verify_hybrid
```

The dirty flag clearing after `pull_verify` in `HybridMemo::get` can be removed since `pull_verify` now clears it internally during finalization. However, keeping it is also safe (idempotent). Remove it for clarity:

```moonbit
        Ok(_) => {
          // dirty flag already cleared by pull_verify
          self.rt.record_dependency(self.cell_id)
```

**Step 4: Run `moon test`**

Expected: All tests pass.

**Step 5: Commit**

```bash
git add cells/verify.mbt cells/hybrid_memo.mbt
git commit -m "refactor: unify pull_verify and pull_verify_hybrid"
```

---

### Task 7: Update whitebox tests

**Files:**
- Modify: `cells/hybrid_wbtest.mbt` (change `push.hybrid_memos` → `pull.memos`, `HybridMemo(i)` index extraction)
- Modify: `cells/soa_wbtest.mbt` (update if references to `pull.memos` count change)
- Modify: `cells/cell_ref_wbtest.mbt` (no changes expected — CellRef variants unchanged)
- Modify: `cells/verify_wbtest.mbt` (update `PullMemoData` references in comments)
- Modify: `cells/cell.mbt` (update comment mentioning `PullMemoData`)
- Modify: `cells/memo_map_wbtest.mbt` (rename `get_pull_memo` → `get_memo_data`, update comment)
- Modify: `cells/durability_wbtest.mbt` (rename `get_pull_memo` → `get_memo_data`)
- Modify: `cells/memo_dep_diff_wbtest.mbt` (rename `get_pull_memo` → `get_memo_data`)

**Step 1: Update `cells/hybrid_wbtest.mbt`**

All `rt.push.hybrid_memos[h_idx]` references become `rt.pull.memos[h_idx]`. The index extraction pattern stays the same since `CellRef::HybridMemo(Int)` is preserved:

```moonbit
  let h_idx = match rt.core.cell_index[h.id().id] {
    HybridMemo(i) => i    // unchanged — CellRef variant preserved
    _ => abort("")
  }
  inspect(rt.pull.memos[h_idx].dirty, content="true")   // ← was push.hybrid_memos
```

The test `"runtime: hybrid_memos and hybrid_dirty start empty"` should be updated:

```moonbit
test "runtime: hybrid_dirty starts empty" {
  let rt = Runtime::new()
  inspect(rt.push.hybrid_dirty.length(), content="0")
}
```

**Step 2: Update `cells/soa_wbtest.mbt`**

The test `"new_memo_id: allocates into pull_memos"` — no change needed since pull memos still go into `pull.memos`.

The test `"runtime: SoA fields exist and start empty"` — no change needed.

**Step 3: Update whitebox tests that call `get_pull_memo`**

In these files, rename `get_pull_memo` → `get_memo_data`:
- `cells/verify_wbtest.mbt` (lines 8, 31, 49, 64)
- `cells/durability_wbtest.mbt` (lines 40, 51, 63)
- `cells/memo_dep_diff_wbtest.mbt` (lines 9, 29)
- `cells/memo_map_wbtest.mbt` (line 9)

**Step 4: Update comments referencing old type names**

In `cells/cell.mbt`:
```moonbit
// All cell metadata now lives in PullSignalData and MemoData
```

In `cells/verify_wbtest.mbt`, update comments mentioning `PullMemoData`:
```
// pull_verify uses MemoData.compute for recomputation.
```

In `cells/push_reactive.mbt` line 5, update comment:
```
/// Uses the same type-erased `compute : () -> Bool` pattern as `MemoData`.
```

**Step 5: Run `moon test`**

Expected: All tests pass (including all 194+ tests across packages).

**Step 6: Commit**

```bash
git add cells/hybrid_wbtest.mbt cells/soa_wbtest.mbt cells/verify_wbtest.mbt \
        cells/durability_wbtest.mbt cells/memo_dep_diff_wbtest.mbt \
        cells/memo_map_wbtest.mbt cells/cell.mbt cells/push_reactive.mbt
git commit -m "test: update whitebox tests for MemoData unification"
```

---

### Task 8: Cleanup, interfaces, and documentation

**Files:**
- Modify: `cells/moon.pkg` (review suppressed warnings)
- Modify: `CLAUDE.md` (update architecture section)
- Run: `moon info && moon fmt`

**Step 1: Review `cells/moon.pkg` warning suppressions**

Warning 7 (`unused_field`) may need updating if `on_change` on hybrid memos or `dirty` on pull memos triggers it. The current suppression should cover this. Verify with `moon check`.

**Step 2: Run `moon info && moon fmt`**

```bash
cd /home/antisatori/ghq/github.com/dowdiness/crdt/loom/incr && moon info && moon fmt
```

**Step 3: Check `.mbti` interface changes**

```bash
git diff *.mbti
```

Expected: Minimal changes — `MemoData` is `priv`, so the public API (`.mbti`) should be unchanged. The `CellRef` enum keeps both variants, so `pkg.generated.mbti` should be identical.

**Step 4: Run full test suite one more time**

```bash
moon test
```

Expected: All tests pass.

**Step 5: Update `CLAUDE.md` architecture section**

In the `Architecture` section of `/home/antisatori/ghq/github.com/dowdiness/crdt/loom/incr/CLAUDE.md`:

- Replace references to `PullMemoData` and `HybridMemoData` with `MemoData`
- Update the SoA storage description: `pull_memos : Array[MemoData]` stores both pull and hybrid memos
- Remove `hybrid_memos` from the `PushState` description
- Note that `CellRef::PullMemo(Int)` and `CellRef::HybridMemo(Int)` both index into `pull.memos`
- Update the file listing: `pull_memo.mbt` → `memo_data.mbt` (if file was renamed) or note it contains `MemoData`

**Step 6: Commit**

```bash
git add -A
git commit -m "docs: update CLAUDE.md and interfaces for MemoData unification"
```

---

## Verification Checklist

After all tasks:

- [ ] `moon check` passes with no new warnings
- [ ] `moon test` passes all tests (should be 194+)
- [ ] `moon test -p dowdiness/incr/tests` passes (integration tests)
- [ ] `git diff *.mbti` shows no public API changes
- [ ] No references to `PullMemoData` or `HybridMemoData` remain in source (only in git history)
- [ ] No references to `get_pull_memo` or `get_hybrid_memo` remain
- [ ] No references to `push.hybrid_memos` remain
- [ ] No references to `pull_verify_hybrid` remain

## Estimated Impact

| Metric | Before | After |
|--------|--------|-------|
| SoA struct definitions | 2 (18 + 18 lines) | 1 (~20 lines) |
| CellOps impl blocks | 14 (7 × 2) | 7 |
| Runtime accessor methods | 2 | 1 |
| force_recompute implementations | 2 (60 + 50 lines) | 1 shared helper (~45 lines) + 2 thin delegators (~20 lines) |
| Verify functions | 2 (230 + 110 lines) | 1 (~250 lines) |
| **Net line reduction** | | **~150–200 lines** |
