# SoA Storage Refactor (Phase 1)

**Goal:** Replace `Runtime.cells : Array[CellMeta?]` with three typed arrays — `pull_signals`, `pull_memos`, and `cell_index` — and a `CellRef` dispatch enum. Zero public API changes. All 200 existing tests must pass throughout.

**Architecture:** See `docs/incr-unified-design.md` §2–3.2, §4.1, §6 for data structure definitions and pseudocode.

**Tech Stack:** MoonBit. Validate with `moon check` and `moon test`.

---

### Scope

In scope:
- `CellRef` enum (`cells/cell_ref.mbt`)
- `PullSignalData`, `PullMemoData` structs with `SignalId[T]`, `MemoId[T]` newtype handles (internal)
- Runtime fields: `pull_signals`, `pull_memos`, `cell_index`
- Helpers: `alloc_cell_id`, `new_signal_id`, `new_memo_id`, `get_changed_at`, `cell_id_for`, `advance_revision`, `commit_pending_signals`, `fire_cell_callbacks`
- Iterative `pull_verify` with explicit `VerifyFrame` stack + `collect_in_progress_path`
- Removal of all `CellMeta` references

Out of scope:
- Subscriber links (Phase 2)
- Push cells, Datalog, Hybrid (Phases 3–5)
- Public API changes

---

### Task 1: Add `CellRef` enum

**Files:**
- Create: `cells/cell_ref.mbt`
- Create: `cells/cell_ref_wbtest.mbt`

**Step 1: Write the failing test**

Create `cells/cell_ref_wbtest.mbt`:

```moonbit
///|
test "cell_ref: PullSignal and PullMemo variants pattern-match correctly" {
  let a : CellRef = CellRef::PullSignal(0)
  let b : CellRef = CellRef::PullMemo(3)
  let ia = match a { PullSignal(i) => i; _ => -1 }
  let ib = match b { PullMemo(i) => i; _ => -1 }
  inspect(ia, content="0")
  inspect(ib, content="3")
}
```

**Step 2: Run test to verify it fails**

Run: `moon test -p dowdiness/incr/cells -f cell_ref_wbtest.mbt -i 0`
Expected: FAIL — `CellRef` type does not exist

**Step 3: Write minimal implementation**

Create `cells/cell_ref.mbt`:

```moonbit
///|
pub enum CellRef {
  PullSignal(index : Int)
  PullMemo(index : Int)
  // PushReactive, PushEffect, Disposed added in Phase 3
  // Relation, Rule added in Phase 4
  // HybridMemo added in Phase 5
}
```

**Step 4: Run test to verify it passes**

Run: `moon test -p dowdiness/incr/cells -f cell_ref_wbtest.mbt -i 0`
Expected: PASS

**Step 5: Run full suite**

Run: `moon test`
Expected: PASS (no existing tests broken — new file is additive)

**Step 6: Commit**

```bash
git add cells/cell_ref.mbt cells/cell_ref_wbtest.mbt
git commit -m "feat(soa): add CellRef enum"
```

---

### Task 2: Add `PullSignalData`, `PullMemoData`, and newtype handles

**Files:**
- Create: `cells/pull_signal.mbt`
- Create: `cells/pull_memo.mbt`

**Step 1: Write the failing test**

Add to `cells/cell_ref_wbtest.mbt`:

```moonbit
///|
test "pull_signal_data: can be constructed" {
  let id = CellId::{ runtime_id: 0, id: 0 }
  let data = PullSignalData::{
    cell_id: id,
    label: None,
    changed_at: Revision::initial(),
    durability: Low,
    subscribers: @hashset.new(),
    on_change: None,
    commit_pending: None,
    rollback_pending: None,
  }
  inspect(data.label, content="None")
}

///|
test "signal_id_memo_id: newtype handles wrap CellId" {
  let cid = CellId::{ runtime_id: 0, id: 5 }
  let sid : SignalId[Int] = SignalId::{ id: cid }
  let mid : MemoId[Int] = MemoId::{ id: cid }
  inspect(sid.id.id, content="5")
  inspect(mid.id.id, content="5")
}
```

**Step 2: Run tests to verify they fail**

Run: `moon test -p dowdiness/incr/cells -f cell_ref_wbtest.mbt`
Expected: FAIL — `PullSignalData`, `SignalId`, `MemoId` do not exist

**Step 3: Write minimal implementation**

Define `PullSignalData` in `cells/pull_signal.mbt` per `docs/incr-unified-design.md` §3.1. Define `PullMemoData` in `cells/pull_memo.mbt` per §3.2. Add newtype handles to `cells/cell_ref.mbt`:

```moonbit
///|
pub struct SignalId[T] { id : CellId }

///|
pub struct MemoId[T] { id : CellId }
```

**Step 4: Run tests to verify they pass**

Run: `moon test -p dowdiness/incr/cells -f cell_ref_wbtest.mbt`
Expected: PASS

**Step 5: Run full suite**

Run: `moon test`
Expected: All existing tests pass

**Step 6: Commit**

```bash
git add cells/pull_signal.mbt cells/pull_memo.mbt cells/cell_ref.mbt cells/cell_ref_wbtest.mbt
git commit -m "feat(soa): add PullSignalData, PullMemoData, SignalId[T], MemoId[T]"
```

---

### Task 3: Add SoA fields and `alloc_cell_id` to Runtime

**Files:**
- Modify: `cells/runtime.mbt`
- Create: `cells/soa_wbtest.mbt`

**Step 1: Write the failing test**

Create `cells/soa_wbtest.mbt`:

```moonbit
///|
test "runtime: SoA fields exist and start empty" {
  let rt = Runtime::new()
  inspect(rt.pull_signals.length(), content="0")
  inspect(rt.pull_memos.length(), content="0")
  inspect(rt.cell_index.length(), content="0")
}

///|
test "runtime: alloc_cell_id populates cell_index" {
  let rt = Runtime::new()
  let cell_id = rt.alloc_cell_id(CellRef::PullSignal(0))
  inspect(cell_id.id, content="0")
  inspect(rt.cell_index.length(), content="1")
  match rt.cell_index[0] {
    PullSignal(i) => inspect(i, content="0")
    _ => abort("expected PullSignal")
  }
}
```

**Step 2: Run tests to verify they fail**

Run: `moon test -p dowdiness/incr/cells -f soa_wbtest.mbt -i 0`
Expected: FAIL — `pull_signals`, `pull_memos`, `cell_index` fields do not exist

**Step 3: Write minimal implementation**

In `cells/runtime.mbt`, add the three SoA fields to `Runtime` alongside the existing `cells` field (do not remove `cells` yet — migrate callers in Tasks 4–5 first). Implement `alloc_cell_id` per `docs/incr-unified-design.md` §6.

**Step 4: Run tests to verify they pass**

Run: `moon test -p dowdiness/incr/cells -f soa_wbtest.mbt`
Expected: PASS

**Step 5: Run full suite**

Run: `moon test`
Expected: All existing tests pass

**Step 6: Commit**

```bash
git add cells/runtime.mbt cells/soa_wbtest.mbt
git commit -m "feat(soa): add pull_signals, pull_memos, cell_index and alloc_cell_id to Runtime"
```

---

### Task 4: Migrate `new_signal_id` and `new_memo_id` to SoA

**Files:**
- Modify: `cells/runtime.mbt`, `cells/signal.mbt`, `cells/memo.mbt`

**Step 1: Write the failing test**

Add to `cells/soa_wbtest.mbt`:

```moonbit
///|
test "new_signal_id: allocates into pull_signals" {
  let rt = Runtime::new()
  let sig = Signal::new(rt, 42)
  inspect(rt.pull_signals.length(), content="1")
  match rt.cell_index[sig.id().id] {
    PullSignal(i) => inspect(i, content="0")
    _ => abort("expected PullSignal")
  }
}

///|
test "new_memo_id: allocates into pull_memos" {
  let rt = Runtime::new()
  let sig = Signal::new(rt, 1)
  let m = Memo::new(rt, () => sig.get())
  let _ = m.get()
  inspect(rt.pull_memos.length(), content="1")
  match rt.cell_index[m.id().id] {
    PullMemo(i) => inspect(i, content="0")
    _ => abort("expected PullMemo")
  }
}
```

**Step 2: Run tests to verify they fail**

Run: `moon test -p dowdiness/incr/cells -f soa_wbtest.mbt`
Expected: FAIL — signals/memos not yet allocated into SoA arrays

**Step 3: Write minimal implementation**

Update `new_signal_id` to push a `PullSignalData` into `rt.pull_signals` and register `PullSignal(idx)` via `alloc_cell_id`. Update `new_memo_id` similarly for `PullMemoData` and `PullMemo(idx)`. See `docs/incr-unified-design.md` §6 for pseudocode.

**Step 4: Run full test suite**

Run: `moon test`
Expected: All existing tests pass

**Step 5: Commit**

```bash
git add cells/runtime.mbt cells/signal.mbt cells/memo.mbt cells/soa_wbtest.mbt
git commit -m "feat(soa): migrate new_signal_id and new_memo_id to SoA arrays"
```

---

### Task 5: Update helpers to dispatch via `CellRef`

**Files:**
- Modify: `cells/runtime.mbt`

**Step 1: Write the failing test**

Add to `cells/soa_wbtest.mbt`:

```moonbit
///|
test "get_changed_at: dispatches via cell_index" {
  let rt = Runtime::new()
  let sig = Signal::new(rt, 1)
  let rev = rt.get_changed_at(sig.id())
  inspect(rev >= Revision::initial(), content="true")
}

///|
test "cell_id_for: round-trips through cell_index" {
  let rt = Runtime::new()
  let sig = Signal::new(rt, 1)
  let cell_id = rt.cell_id_for(rt.cell_index[sig.id().id])
  inspect(cell_id == sig.id(), content="true")
}
```

**Step 2: Run tests to verify they fail**

Run: `moon test -p dowdiness/incr/cells -f soa_wbtest.mbt`
Expected: FAIL — helpers still read from `cells` array, not SoA

**Step 3: Write minimal implementation**

Update `get_changed_at`, `cell_id_for`, `advance_revision`, `commit_pending_signals`, and `fire_cell_callbacks` to dispatch via `match self.cell_index[cell_id.id]` as specified in `docs/incr-unified-design.md` §6.

**Step 4: Run full test suite**

Run: `moon test`
Expected: All existing tests pass

**Step 5: Commit**

```bash
git add cells/runtime.mbt cells/soa_wbtest.mbt
git commit -m "feat(soa): update helpers to dispatch via CellRef"
```

---

### Task 6: Replace `maybe_changed_after` with iterative `pull_verify`

**Files:**
- Modify: `cells/verify.mbt`
- Modify: `cells/runtime.mbt` (add `collect_in_progress_path`)
- Create: `cells/pull_verify_wbtest.mbt`

**Step 1: Write the failing test**

Create `cells/pull_verify_wbtest.mbt`:

```moonbit
///|
test "pull_verify: signal always returns Ok" {
  let rt = Runtime::new()
  let sig = Signal::new(rt, 1)
  let result = rt.pull_verify(sig.id())
  inspect(result, content="Ok(())")
}

///|
test "pull_verify: up-to-date memo returns Ok without recompute" {
  let rt = Runtime::new()
  let sig = Signal::new(rt, 1)
  let mut count = 0
  let m = Memo::new(rt, () => { count += 1; sig.get() })
  let _ = m.get()
  inspect(count, content="1")
  let _ = rt.pull_verify(m.id())
  inspect(count, content="1")
}

///|
test "pull_verify: stale memo recomputes on next get" {
  let rt = Runtime::new()
  let sig = Signal::new(rt, 1)
  let m = Memo::new(rt, () => sig.get() + 10)
  let _ = m.get()
  sig.set(5)
  let _ = rt.pull_verify(m.id())
  inspect(m.get(), content="15")
}
```

**Step 2: Run tests to verify they fail**

Run: `moon test -p dowdiness/incr/cells -f pull_verify_wbtest.mbt`
Expected: FAIL — `rt.pull_verify` does not exist

**Step 3: Write minimal implementation**

In `cells/verify.mbt`, implement `pull_verify` with an explicit `VerifyFrame` stack as specified in `docs/incr-unified-design.md` §4.1.

In `cells/runtime.mbt`, add `collect_in_progress_path` per §6.

Wire `pull_verify` into `Memo::get` to replace all calls to `maybe_changed_after`.

**Step 4: Run full test suite**

Run: `moon test`
Expected: All 200 existing tests pass

**Step 5: Commit**

```bash
git add cells/verify.mbt cells/runtime.mbt cells/pull_verify_wbtest.mbt
git commit -m "feat(soa): implement iterative pull_verify with VerifyFrame stack"
```

---

### Task 7: Remove `CellMeta` entirely

**Files:**
- Modify/Delete: `cells/cell.mbt`
- Modify: `cells/runtime.mbt`

**Step 1: Audit remaining references**

```bash
grep -rn "CellMeta" cells/
```

Resolve any remaining references before proceeding.

**Step 2: Remove `cells` field from Runtime**

Delete `cells : Array[CellMeta?]` from `Runtime`. Remove or gut `cells/cell.mbt`.

**Step 3: Run full suite**

```bash
moon check && moon test
```

Expected: `moon check` clean; all 200 tests pass.

**Step 4: Commit**

```bash
git add cells/
git commit -m "feat(soa): remove CellMeta; SoA refactor complete"
```

---

### Acceptance Criteria

- `moon test` passes all 200 existing tests
- `moon check` reports no type errors
- `Runtime` uses `pull_signals : Array[PullSignalData]`, `pull_memos : Array[PullMemoData]`, `cell_index : Array[CellRef]`
- `maybe_changed_after` replaced by iterative `pull_verify` with explicit `VerifyFrame` stack
- `collect_in_progress_path` helper exists for cycle detection
- No `CellMeta` references remain in the codebase
- `SignalId[T]` and `MemoId[T]` newtype handles defined in `cells/cell_ref.mbt`
