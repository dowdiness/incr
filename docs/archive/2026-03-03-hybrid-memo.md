# Hybrid Memo (Phase 5)

**Goal:** Add `HybridMemo[T]`: a memo that receives dirty flags eagerly (like push) but verifies lazily on `get()` (like pull). Skips the full dependency walk when the cell hasn't been dirtied — an optimization over pure pull mode.

**Architecture:** See `docs/incr-unified-design.md` §10 Phase 5 for data structure and algorithm. Uses Option A for dirty-flag propagation: `HybridMemo` cases are handled inside `enqueue_push_subscribers`, setting a dirty flag and adding to a flat `hybrid_dirty` list (not the level-sorted queue).

**Prerequisite:** Phase 2 (subscriber links) and Phase 3 (push reactives) complete.

**Tech Stack:** MoonBit. Validate with `moon check` and `moon test`.

---

### Scope

In scope:
- `HybridMemo` variant added to `CellRef`
- `HybridMemoData` struct with `dirty : Bool` flag
- `hybrid_memos : Array[HybridMemoData]`, `hybrid_dirty : Array[CellId]` added to Runtime
- `HybridMemo[T]` user-facing struct with fast path in `get()`
- `HybridMemo` case added to `enqueue_push_subscribers` in `propagate.mbt`
- `pull_verify` extended to handle `HybridMemo` frames
- `get_subscribers`, `get_subscribers_mut`, `get_changed_at`, `cell_id_for` extended

Out of scope:
- Level-based propagation for HybridMemo (hybrid memos are not in the priority queue)

---

### Task 1: Add `HybridMemo` variant to `CellRef`

**Files:**
- Modify: `cells/cell_ref.mbt`
- Create: `cells/hybrid_wbtest.mbt`

**Step 1: Write the failing test**

Create `cells/hybrid_wbtest.mbt`:

```moonbit
///|
test "cell_ref: HybridMemo variant pattern-matches correctly" {
  let a : CellRef = CellRef::HybridMemo(4)
  let ia = match a { HybridMemo(i) => i; _ => -1 }
  inspect(ia, content="4")
}
```

**Step 2: Run test to verify it fails**

Run: `moon test -p dowdiness/incr/cells -f hybrid_wbtest.mbt -i 0`
Expected: FAIL — `HybridMemo` variant does not exist

**Step 3: Write minimal implementation**

In `cells/cell_ref.mbt`, add `HybridMemo(index : Int)` to the `CellRef` enum. Update all existing `match` expressions to add wildcard arms.

**Step 4: Run test to verify it passes**

Run: `moon test -p dowdiness/incr/cells -f hybrid_wbtest.mbt -i 0`
Expected: PASS

**Step 5: Run full suite**

Run: `moon test`
Expected: All existing tests pass

**Step 6: Commit**

```bash
git add cells/cell_ref.mbt cells/hybrid_wbtest.mbt
git commit -m "feat(hybrid): add HybridMemo variant to CellRef"
```

---

### Task 2: Add `HybridMemoData` and Runtime arrays

**Files:**
- Create: `cells/hybrid_memo.mbt`
- Modify: `cells/runtime.mbt`

**Step 1: Write the failing test**

Add to `cells/hybrid_wbtest.mbt`:

```moonbit
///|
test "runtime: hybrid_memos and hybrid_dirty start empty" {
  let rt = Runtime::new()
  inspect(rt.hybrid_memos.length(), content="0")
  inspect(rt.hybrid_dirty.length(), content="0")
}
```

**Step 2: Run test to verify it fails**

Run: `moon test -p dowdiness/incr/cells -f hybrid_wbtest.mbt`
Expected: FAIL — `hybrid_memos`, `hybrid_dirty` fields do not exist

**Step 3: Write minimal implementation**

In `cells/hybrid_memo.mbt`, define `HybridMemoData` per `docs/incr-unified-design.md` §10. Key field vs `PullMemoData`: adds `mut dirty : Bool`.

In `cells/runtime.mbt`, add:

```moonbit
hybrid_memos : Array[HybridMemoData]
hybrid_dirty : Array[CellId]
```

Initialize both to `[]` in `Runtime::new()`.

**Step 4: Run tests to verify they pass**

Run: `moon test -p dowdiness/incr/cells -f hybrid_wbtest.mbt`
Expected: PASS

**Step 5: Run full suite**

Run: `moon test`
Expected: All existing tests pass

**Step 6: Commit**

```bash
git add cells/hybrid_memo.mbt cells/runtime.mbt cells/hybrid_wbtest.mbt
git commit -m "feat(hybrid): add HybridMemoData and hybrid arrays to Runtime"
```

---

### Task 3: Implement `HybridMemo[T]::get` with fast path

**Files:**
- Modify: `cells/hybrid_memo.mbt`
- Modify: `cells/verify.mbt` (extend `pull_verify` for HybridMemo frames)

**Step 1: Write the failing test**

Add to `cells/hybrid_wbtest.mbt`:

```moonbit
///|
test "hybrid memo: basic get() returns correct value" {
  let rt = Runtime::new()
  let s = Signal::new(rt, 1)
  let h = HybridMemo::new(rt, () => s.get() * 2)
  inspect(h.get(), content="2")
  s.set(5)
  inspect(h.get(), content="10")
}

///|
test "hybrid memo: fast path skips compute when not dirtied" {
  let rt = Runtime::new()
  let s = Signal::new(rt, 1)
  let unrelated = Signal::new(rt, 99)
  let mut count = 0
  let h = HybridMemo::new(rt, () => { count += 1; s.get() })
  let _ = h.get()
  inspect(count, content="1")
  unrelated.set(100)
  let _ = h.get()
  inspect(count, content="1")  // unrelated change → not dirtied → no recompute
}

///|
test "hybrid memo: dirty flag triggers recompute on get" {
  let rt = Runtime::new()
  let s = Signal::new(rt, 1)
  let h = HybridMemo::new(rt, () => s.get() + 10)
  let _ = h.get()
  s.set(5)  // push propagation sets h.dirty = true
  let h_idx = match rt.cell_index[h.id().id] { HybridMemo(i) => i; _ => abort("") }
  inspect(rt.hybrid_memos[h_idx].dirty, content="true")
  inspect(h.get(), content="15")  // triggers recompute; dirty cleared
  inspect(rt.hybrid_memos[h_idx].dirty, content="false")
}
```

**Step 2: Run tests to verify they fail**

Run: `moon test -p dowdiness/incr/cells -f hybrid_wbtest.mbt`
Expected: FAIL — `HybridMemo::new` does not exist

**Step 3: Write minimal implementation**

In `cells/hybrid_memo.mbt`, implement `HybridMemo[T]::get`:

```moonbit
pub fn[T : Eq] HybridMemo::get(self : HybridMemo[T]) -> T {
  let idx = match self.rt.cell_index[self.id.id.id] {
    HybridMemo(i) => i
    _ => abort("HybridMemo::get: invalid cell kind")
  }
  let h = self.rt.hybrid_memos[idx]
  if not(h.dirty) && h.verified_at >= self.rt.revision() {
    // Fast path: not dirtied and verified this revision
    return self.value_ref.val.unwrap()
  }
  // Slow path: dirty or stale — fall through to pull verification
  self.rt.pull_verify_hybrid(self.id.id) |> ignore
  h.dirty = false
  self.value_ref.val.unwrap()
}
```

Extend `pull_verify` (or add `pull_verify_hybrid`) in `cells/verify.mbt` to push `HybridMemo` frames onto the verify stack. The trigger condition is `h.dirty || h.verified_at < self.revision`. See `docs/incr-unified-design.md` §10.

**Step 4: Run tests to verify they pass**

Run: `moon test -p dowdiness/incr/cells -f hybrid_wbtest.mbt`
Expected: PASS

**Step 5: Commit**

```bash
git add cells/hybrid_memo.mbt cells/verify.mbt cells/hybrid_wbtest.mbt
git commit -m "feat(hybrid): implement HybridMemo::get with fast path"
```

---

### Task 4: Add dirty-flag propagation in `enqueue_push_subscribers`

**Files:**
- Modify: `cells/propagate.mbt`
- Modify: `cells/runtime.mbt` (`commit_batch`)

**Step 1: Write the failing test**

Add to `cells/hybrid_wbtest.mbt`:

```moonbit
///|
test "hybrid memo: dirty flag set by push propagation before get()" {
  let rt = Runtime::new()
  let s = Signal::new(rt, 1)
  let h = HybridMemo::new(rt, () => s.get())
  let _ = h.get()
  s.set(2)
  // After s.set(), push propagation should have set h.dirty = true
  let h_idx = match rt.cell_index[h.id().id] { HybridMemo(i) => i; _ => abort("") }
  inspect(rt.hybrid_memos[h_idx].dirty, content="true")
}

///|
test "hybrid memo: backdating — unchanged value does not bump changed_at" {
  let rt = Runtime::new()
  let s = Signal::new(rt, 1)
  let h = HybridMemo::new(rt, () => s.get())
  let _ = h.get()
  let h_idx = match rt.cell_index[h.id().id] { HybridMemo(i) => i; _ => abort("") }
  let before = rt.hybrid_memos[h_idx].changed_at
  s.set(1)  // same value → signal backdating → h may not be dirtied
  let _ = h.get()
  inspect(rt.hybrid_memos[h_idx].changed_at == before, content="true")
}
```

**Step 2: Run tests to verify they fail**

Run: `moon test -p dowdiness/incr/cells -f hybrid_wbtest.mbt`
Expected: FAIL — `enqueue_push_subscribers` does not handle `HybridMemo`

**Step 3: Write minimal implementation**

In `cells/propagate.mbt`, inside `enqueue_push_subscribers`, add `HybridMemo` case (Option A from design doc):

```moonbit
HybridMemo(i) => {
  if not(self.hybrid_memos[i].dirty) {
    self.hybrid_memos[i].dirty = true
    self.hybrid_dirty.push(sub_id)
  }
}
```

In `cells/runtime.mbt`, clear `hybrid_dirty` at the start of each `commit_batch` (alongside `batch_pending_signals`).

**Step 4: Run full test suite**

Run: `moon test`
Expected: All existing tests pass

**Step 5: Commit**

```bash
git add cells/propagate.mbt cells/runtime.mbt cells/hybrid_wbtest.mbt
git commit -m "feat(hybrid): add HybridMemo dirty-flag propagation in enqueue_push_subscribers"
```

---

### Task 5: Extend helpers for `HybridMemo`

**Files:**
- Modify: `cells/runtime.mbt`

**Step 1: Write the failing test**

Add to `cells/hybrid_wbtest.mbt`:

```moonbit
///|
test "get_subscribers: HybridMemo arm returns subscribers" {
  let rt = Runtime::new()
  let h = HybridMemo::new(rt, () => 42)
  let _ = h.get()
  let subs = rt.get_subscribers(rt.cell_index[h.id().id]).collect()
  inspect(subs.length(), content="0")  // leaf node, no subscribers yet
}
```

**Step 2: Run test to verify it fails**

Run: `moon test -p dowdiness/incr/cells -f hybrid_wbtest.mbt`
Expected: FAIL — helpers not yet extended for `HybridMemo`

**Step 3: Write minimal implementation**

In `cells/runtime.mbt`, extend `get_subscribers`, `get_subscribers_mut`, `get_changed_at`, and `cell_id_for` with `HybridMemo` arms per `docs/incr-unified-design.md` §10:

```moonbit
// get_subscribers:
HybridMemo(idx) => self.hybrid_memos[idx].subscribers.iter()

// get_subscribers_mut:
HybridMemo(idx) => self.hybrid_memos[idx].subscribers

// get_changed_at:
HybridMemo(idx) => self.hybrid_memos[idx].changed_at

// cell_id_for:
HybridMemo(idx) => self.hybrid_memos[idx].cell_id
```

**Step 4: Run full test suite**

Run: `moon test`
Expected: All existing tests pass

**Step 5: Commit**

```bash
git add cells/runtime.mbt cells/hybrid_wbtest.mbt
git commit -m "feat(hybrid): extend helpers with HybridMemo arms"
```

---

### Acceptance Criteria

- All Phase 1 + Phase 2 + Phase 3 tests pass
- All Phase 5 tests above pass
- `moon check` has no type errors
- Fast path test confirms `compute` is not called when `dirty = false` and `verified_at` is current
- Dirty flag is set by push propagation before `get()` is called
- `pull_verify` correctly handles `HybridMemo` frames on the explicit stack
- Backdating: unchanged value does not bump `changed_at`
