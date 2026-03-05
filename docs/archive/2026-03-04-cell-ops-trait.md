# CellOps & Committable Trait Object Design

> **For Claude:** REQUIRED SUB-SKILL: Use superpowers:executing-plans to implement this plan task-by-task.

**Goal:** Add a `CellOps` trait so cross-kind runtime helpers dispatch through a trait object instead of a `CellRef` match, and add a `Committable` trait so `commit_batch` dispatches directly through a `&Committable` array instead of looking up `PullSignalData` by `CellId`.

**Architecture:** Define `CellOps` with 6 object-safe methods (`cell_id`, `changed_at`, `set_changed_at`, `subscribers`, `label`, `durability`), implement it on both SoA structs, add `cell_ops : Array[&CellOps]` to `Runtime`, and rewrite nine helpers to use it. Define `Committable` with 4 methods (`do_commit`, `cell_id`, `durability`, `fire_on_change_if_set`), implement on `PullSignalData`, replace `batch_pending_signals : Array[CellId]` with `batch_pending : Array[&Committable]`, and simplify `commit_batch`. Phase 3 cell kinds (`PushReactive`, `PushEffect`, etc.) then only need to implement two traits instead of adding arms to nine match statements.

**Tech Stack:** MoonBit, SoA layout, trait objects (`&TraitName`)

---

### Task 1: Define the CellOps trait and write a failing whitebox test

**Files:**
- Create: `cells/cell_ops.mbt`
- Create: `cells/cell_ops_wbtest.mbt`

**Background:** MoonBit trait objects use `&TraitName` syntax. Object safety requires `Self` appears exactly once as the first (and only receiver) parameter. All six methods satisfy this. `subscribers` returns `@hashset.HashSet[CellId]`, which is a heap-allocated reference type — mutations on the returned set are visible in the SoA struct.

**Step 1: Write the failing test first**

Create `cells/cell_ops_wbtest.mbt`:

```moonbit
///|
test "cell_ops: signal has ops at its id index" {
  let rt = Runtime::new()
  let sig = Signal::new(rt, 42)
  // Once cell_ops is populated, rt.cell_ops[sig.id().id].cell_id() == sig.id()
  inspect(rt.cell_ops.length(), content="1")
}

///|
test "cell_ops: memo has ops at its id index" {
  let rt = Runtime::new()
  let m = Memo::new(rt, () => 0)
  inspect(rt.cell_ops.length(), content="1")
}
```

**Step 2: Run tests to verify they fail**

```bash
moon test -p dowdiness/incr/cells -f cell_ops_wbtest.mbt
```

Expected: compile error — `Runtime` has no `cell_ops` field.

**Step 3: Write the trait definition**

Create `cells/cell_ops.mbt`:

```moonbit
///|
/// Uniform interface for all cell kinds in the dependency graph.
///
/// Every cell kind (PullSignal, PullMemo, and future Phase 3+ kinds) implements
/// this trait so Runtime helpers can dispatch without a CellRef match.
///
/// # Object Safety
///
/// All methods take `Self` as the sole receiver (first param, once only).
/// The trait can therefore be used as `&CellOps` in Arrays and function params.
///
/// # Usage
///
/// `Runtime.cell_ops : Array[&CellOps]` is indexed by `CellId.id` — the same
/// index used by `cell_index : Array[CellRef]`. Prefer `cell_ops` for helpers
/// that need only these shared fields; use `cell_index` + direct SoA access in
/// hot paths like `pull_verify`.
trait CellOps {
  cell_id(Self) -> CellId
  changed_at(Self) -> Revision
  set_changed_at(Self, Revision) -> Unit
  subscribers(Self) -> @hashset.HashSet[CellId]
  label(Self) -> String?
  durability(Self) -> Durability
}
```

**Step 4: Run moon check to verify syntax**

```bash
moon check
```

Expected: OK (trait with no impls yet is valid).

**Step 5: Commit**

```bash
git add cells/cell_ops.mbt cells/cell_ops_wbtest.mbt
git commit -m "feat(cell-ops): define CellOps trait and failing tests"
```

---

### Task 2: Implement CellOps for PullSignalData

**Files:**
- Modify: `cells/pull_signal.mbt`

**Background:** `PullSignalData` fields `cell_id`, `changed_at`, `durability`, `subscribers`, `label` are all direct struct fields. `set_changed_at` mutates `self.changed_at`; this works because `Array[PullSignalData]` elements have reference semantics in MoonBit (heap-allocated, not copied on access).

**Step 1: Add the impl**

Append to `cells/pull_signal.mbt`:

```moonbit
///|
/// CellOps dispatch for pull-signal cells.
impl CellOps for PullSignalData {
  fn cell_id(self) -> CellId { self.cell_id }

  fn changed_at(self) -> Revision { self.changed_at }

  fn set_changed_at(self, rev : Revision) -> Unit {
    self.changed_at = rev
  }

  fn subscribers(self) -> @hashset.HashSet[CellId] { self.subscribers }

  fn label(self) -> String? { self.label }

  fn durability(self) -> Durability { self.durability }
}
```

**Step 2: Run moon check**

```bash
moon check
```

Expected: OK.

**Step 3: Commit**

```bash
git add cells/pull_signal.mbt
git commit -m "feat(cell-ops): implement CellOps for PullSignalData"
```

---

### Task 3: Implement CellOps for PullMemoData

**Files:**
- Modify: `cells/pull_memo.mbt`

**Step 1: Add the impl**

Append to `cells/pull_memo.mbt`:

```moonbit
///|
/// CellOps dispatch for pull-memo cells.
impl CellOps for PullMemoData {
  fn cell_id(self) -> CellId { self.cell_id }

  fn changed_at(self) -> Revision { self.changed_at }

  fn set_changed_at(self, rev : Revision) -> Unit {
    self.changed_at = rev
  }

  fn subscribers(self) -> @hashset.HashSet[CellId] { self.subscribers }

  fn label(self) -> String? { self.label }

  fn durability(self) -> Durability { self.durability }
}
```

**Step 2: Run moon check**

```bash
moon check
```

Expected: OK.

**Step 3: Commit**

```bash
git add cells/pull_memo.mbt
git commit -m "feat(cell-ops): implement CellOps for PullMemoData"
```

---

### Task 4: Add cell_ops array to Runtime and populate it at cell creation

**Files:**
- Modify: `cells/runtime.mbt`
- Modify: `cells/memo.mbt`

**Background:** `cell_ops : Array[&CellOps]` is indexed by `CellId.id`. Each entry is created when a cell is allocated:
- For signals: at the end of `Runtime::new_signal_id`, after pushing to `pull_signals`, get the reference back and store it.
- For memos: inline in `Memo::new` (because memo creation is inline there due to the type-erasure construction cycle), after pushing to `rt.pull_memos`.

`PullSignalData` is stored in `pull_signals : Array[PullSignalData]`; after `pull_signals.push(...)`, `pull_signals[idx]` returns the same reference. We coerce it to `&CellOps` with an explicit type annotation.

**Step 1: Add cell_ops to Runtime struct**

In `cells/runtime.mbt`, modify the `Runtime` struct (around line 64):

```moonbit
pub(all) struct Runtime {
  priv runtime_id : Int
  priv mut current_revision : Revision
  priv mut next_cell_id : Int
  priv tracking_stack : Array[ActiveQuery]
  priv durability_last_changed : FixedArray[Revision]
  priv mut batch_depth : Int
  priv batch_pending_signals : Array[CellId]
  priv batch_frames : Array[BatchFrame]
  priv mut batch_max_durability : Durability
  priv mut on_change : (() -> Unit)?
  // SoA storage arrays
  priv pull_signals : Array[PullSignalData]
  priv pull_memos : Array[PullMemoData]
  priv cell_index : Array[CellRef]
  // Trait object dispatch (indexed by CellId.id, parallel to cell_index)
  priv cell_ops : Array[&CellOps]

  fn new(on_change? : () -> Unit) -> Runtime
}
```

**Step 2: Initialize cell_ops in Runtime::new**

In `Runtime::new()` (around line 110), add `cell_ops: []` to the struct literal:

```moonbit
pub fn Runtime::new(on_change? : () -> Unit) -> Runtime {
  let id = next_runtime_id.val
  next_runtime_id.val = next_runtime_id.val + 1
  {
    runtime_id: id,
    current_revision: Revision::initial(),
    next_cell_id: 0,
    tracking_stack: [],
    durability_last_changed: FixedArray::make(
      @incr_types.DURABILITY_COUNT,
      Revision::initial(),
    ),
    batch_depth: 0,
    batch_pending_signals: [],
    batch_frames: [],
    batch_max_durability: Low,
    on_change,
    pull_signals: [],
    pull_memos: [],
    cell_index: [],
    cell_ops: [],
  }
}
```

**Step 3: Populate cell_ops in new_signal_id**

In `Runtime::new_signal_id` (around line 196), add the `cell_ops.push` after `pull_signals.push`:

```moonbit
fn Runtime::new_signal_id(
  self : Runtime,
  durability : Durability,
  label : String?,
) -> CellId {
  let idx = self.pull_signals.length()
  let cell_id = self.alloc_cell_id(PullSignal(idx))
  self.pull_signals.push({
    cell_id,
    label,
    changed_at: Revision::initial(),
    durability,
    subscribers: @hashset.new(),
    on_change: None,
    commit_pending: None,
    rollback_pending: None,
  })
  let ops : &CellOps = self.pull_signals[idx]
  self.cell_ops.push(ops)
  cell_id
}
```

**Step 4: Populate cell_ops in Memo::new**

In `cells/memo.mbt`, in `Memo::new` (around line 60), add `cell_ops.push` after `rt.pull_memos.push(...)`:

```moonbit
pub fn[T : Eq] Memo::new(
  rt : Runtime,
  compute : () -> T,
  label? : String,
) -> Memo[T] {
  let memo_idx = rt.pull_memos.length()
  let cell_id = rt.alloc_cell_id(PullMemo(memo_idx))
  let memo : Memo[T] = { label, rt, cell_id, compute, value: None }
  rt.pull_memos.push({
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
  })
  let ops : &CellOps = rt.pull_memos[memo_idx]
  rt.cell_ops.push(ops)
  memo
}
```

**Step 5: Run moon check**

```bash
moon check
```

Expected: OK.

**Step 6: Run tests to verify cell_ops array is populated**

```bash
moon test -p dowdiness/incr/cells -f cell_ops_wbtest.mbt
```

Expected: PASS for both tests (length checks).

**Step 7: Extend the tests with richer assertions**

Update `cells/cell_ops_wbtest.mbt`:

```moonbit
///|
test "cell_ops: signal has ops at its id index" {
  let rt = Runtime::new()
  let sig = Signal::new(rt, 42)
  inspect(rt.cell_ops.length(), content="1")
  let ops = rt.cell_ops[sig.id().id]
  inspect(ops.cell_id() == sig.id(), content="true")
  inspect(ops.label(), content="None")
}

///|
test "cell_ops: memo has ops at its id index" {
  let rt = Runtime::new()
  let m = Memo::new(rt, () => 0)
  inspect(rt.cell_ops.length(), content="1")
  let ops = rt.cell_ops[m.id().id]
  inspect(ops.cell_id() == m.id(), content="true")
}

///|
test "cell_ops: set_changed_at mutates the SoA struct" {
  let rt = Runtime::new()
  let sig = Signal::new(rt, 1)
  let ops = rt.cell_ops[sig.id().id]
  let rev1 = Revision::next(Revision::initial())
  ops.set_changed_at(rev1)
  inspect(rt.get_changed_at(sig.id()) == rev1, content="true")
}

///|
test "cell_ops: signal and memo ids are distinct when both exist" {
  let rt = Runtime::new()
  let sig = Signal::new(rt, 1)
  let m = Memo::new(rt, () => sig.get())
  inspect(rt.cell_ops.length(), content="2")
  inspect(rt.cell_ops[sig.id().id].cell_id() == sig.id(), content="true")
  inspect(rt.cell_ops[m.id().id].cell_id() == m.id(), content="true")
}
```

**Step 8: Run the extended tests**

```bash
moon test -p dowdiness/incr/cells -f cell_ops_wbtest.mbt
```

Expected: all PASS.

**Step 9: Run the full test suite**

```bash
moon test
```

Expected: all 212 (plus the 4 new) tests pass.

**Step 10: Commit**

```bash
git add cells/runtime.mbt cells/memo.mbt cells/cell_ops_wbtest.mbt
git commit -m "feat(cell-ops): add cell_ops array to Runtime, populate at cell creation"
```

---

### Task 5: Refactor runtime helpers to dispatch through cell_ops

**Files:**
- Modify: `cells/runtime.mbt`

**Background:** Nine helpers currently have a two-arm `CellRef` match. After this task each becomes a single `cell_ops[id.id].method()` call. The bounds/runtime_id guards stay. `pull_verify` is NOT changed — it is a hot path that requires direct SoA access for the `PullVerifyFrame` stack. `cell_info` and `dependents` both use `cell_ops` for shared fields but still need a `cell_index` match for memo-only fields (`verified_at`, `dependencies`).

**Which helpers to rewrite (complete list):**
1. `get_changed_at` — replace match with `self.cell_ops[id.id].changed_at()`
2. `get_durability` — replace match with `self.cell_ops[id.id].durability()`
3. `cell_id_for` — replace match with `self.cell_ops[cref_idx].cell_id()` — but `cell_id_for` takes a `CellRef` not a `CellId`. Rewrite to look up via the SoA index stored in the `CellRef` variant.
4. `get_subscribers` — replace match with `self.cell_ops[cell_id.id].subscribers().iter()`
5. `get_subscribers_mut` — replace match with `self.cell_ops[cell_id.id].subscribers()`
6. `remove_subscriber` — replace match with `self.cell_ops[dep.id].subscribers().remove(subscriber)`
7. `add_subscriber` — replace match with `self.cell_ops[dep.id].subscribers().add(subscriber)`
8. `mark_input_changed` — uses `get_pull_signal` internally, cannot use cell_ops (signal-specific). Leave as-is.
9. `cell_info` — use cell_ops for `cell_id`, `changed_at`, `label`, `durability`, `subscribers`; keep match for `verified_at`/`dependencies`.
10. `dependents` — use `cell_ops[id.id].subscribers()`

**Step 1: Rewrite the small helpers**

Replace the bodies of these functions in `cells/runtime.mbt`. Replace everything from the `match self.cell_index[...] {` to the closing `}` with the one-liner.

`get_changed_at` (after bounds/runtime_id guard, around line 239):
```moonbit
fn Runtime::get_changed_at(self : Runtime, id : CellId) -> Revision {
  if id.runtime_id != self.runtime_id {
    abort("Cell belongs to a different Runtime")
  }
  if id.id < 0 || id.id >= self.cell_index.length() {
    abort("get_changed_at: cell_id out of bounds: " + id.id.to_string())
  }
  self.cell_ops[id.id].changed_at()
}
```

`get_durability` (around line 254):
```moonbit
fn Runtime::get_durability(self : Runtime, id : CellId) -> Durability {
  self.cell_ops[id.id].durability()
}
```

`cell_id_for` takes a `CellRef`, not a `CellId`. The approach: extract the SoA index from the `CellRef` and index `cell_ops` using the `CellId` stored in the SoA entry. Since we have `cell_ops` indexed by `CellId.id`, we need the `CellId.id` not the SoA index. The cleanest fix: extract the `cell_id` from `cell_ops` using the SoA idx stored in the CellRef to find the right ops entry. Actually `cell_id_for` doesn't know `CellId.id` from just a `CellRef(soa_idx)`. We still need the match to go from SoA idx → CellId. Leave `cell_id_for` as-is (it's called rarely).

`get_subscribers` (around line 319):
```moonbit
fn Runtime::get_subscribers(self : Runtime, cell_id : CellId) -> Iter[CellId] {
  if cell_id.runtime_id != self.runtime_id {
    abort("Cell belongs to a different Runtime")
  }
  if cell_id.id < 0 || cell_id.id >= self.cell_index.length() {
    abort("get_subscribers: cell_id out of bounds: " + cell_id.id.to_string())
  }
  self.cell_ops[cell_id.id].subscribers().iter()
}
```

`get_subscribers_mut` (around line 338):
```moonbit
fn Runtime::get_subscribers_mut(
  self : Runtime,
  cell_id : CellId,
) -> @hashset.HashSet[CellId] {
  if cell_id.runtime_id != self.runtime_id {
    abort("Cell belongs to a different Runtime")
  }
  if cell_id.id < 0 || cell_id.id >= self.cell_index.length() {
    abort(
      "get_subscribers_mut: cell_id out of bounds: " + cell_id.id.to_string(),
    )
  }
  self.cell_ops[cell_id.id].subscribers()
}
```

`remove_subscriber` (around line 358):
```moonbit
fn Runtime::remove_subscriber(
  self : Runtime,
  dep : CellId,
  subscriber : CellId,
) -> Unit {
  self.cell_ops[dep.id].subscribers().remove(subscriber)
}
```

`add_subscriber` (around line 371):
```moonbit
fn Runtime::add_subscriber(
  self : Runtime,
  dep : CellId,
  subscriber : CellId,
) -> Unit {
  self.cell_ops[dep.id].subscribers().add(subscriber)
}
```

**Step 2: Rewrite cell_info to use cell_ops for shared fields**

`cell_info` (around line 457). Use `cell_ops` for shared fields, keep `cell_index` match for memo-only fields:

```moonbit
pub fn Runtime::cell_info(self : Runtime, id : CellId) -> CellInfo? {
  if id.runtime_id != self.runtime_id {
    return None
  }
  if id.id < 0 || id.id >= self.cell_index.length() {
    return None
  }
  let ops = self.cell_ops[id.id]
  match self.cell_index[id.id] {
    PullSignal(_) =>
      Some(CellInfo::{
        label: ops.label(),
        id,
        changed_at: ops.changed_at(),
        verified_at: ops.changed_at(), // signals are always verified
        durability: ops.durability(),
        dependencies: [],
        subscribers: snapshot_subscribers(ops.subscribers()),
      })
    PullMemo(idx) => {
      let memo = self.pull_memos[idx]
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
  }
}
```

**Step 3: Rewrite dependents to use cell_ops**

`dependents` (around line 522):

```moonbit
pub fn Runtime::dependents(self : Runtime, id : CellId) -> Array[CellId] {
  if id.runtime_id != self.runtime_id {
    return []
  }
  if id.id < 0 || id.id >= self.cell_index.length() {
    return []
  }
  snapshot_subscribers(self.cell_ops[id.id].subscribers())
}
```

**Step 4: Run moon check**

```bash
moon check
```

Expected: OK.

**Step 5: Run all tests**

```bash
moon test
```

Expected: all tests pass (count same as before plus Task 4's new tests).

**Step 6: Commit**

```bash
git add cells/runtime.mbt
git commit -m "refactor(cell-ops): dispatch runtime helpers through CellOps trait objects"
```

---

### Task 6: Define the Committable trait and implement it on PullSignalData

**Files:**
- Modify: `cells/cell_ops.mbt`
- Modify: `cells/pull_signal.mbt`
- Create: `cells/committable_wbtest.mbt`

**Background:** `Committable` gives `commit_batch` a uniform interface to iterate over batched signals without looking up `PullSignalData` by `CellId`. The implementation delegates to the existing `commit_pending` closure on `PullSignalData` — closures are preserved for now. `rollback_pending` on `PullSignalData` is dead code (it's set but never invoked — only checked for `Some` as an invariant), so we remove it. `cell_id` and `durability` on the trait let `commit_batch` and `recompute_batch_max_durability` avoid any SoA lookups.

**Step 1: Write the failing test**

Create `cells/committable_wbtest.mbt`:

```moonbit
///|
test "committable: batch_pending holds entry after set" {
  let rt = Runtime::new()
  let sig = Signal::new(rt, 1)
  rt.batch_depth = 1  // simulate batch
  sig.set(2)
  rt.batch_depth = 0
  // With Committable, batch_pending should have 1 entry
  inspect(rt.batch_pending.length(), content="1")
}
```

**Step 2: Run test to see it fail**

```bash
moon test -p dowdiness/incr/cells -f committable_wbtest.mbt
```

Expected: compile error — `batch_pending` field doesn't exist yet.

**Step 3: Define Committable trait in cell_ops.mbt**

Append to `cells/cell_ops.mbt`:

```moonbit
///|
/// Interface for signal cells that have pending values during a batch.
///
/// Implemented by `PullSignalData`. Stored as `&Committable` in
/// `Runtime.batch_pending` so `commit_batch` can iterate and dispatch
/// without a per-entry `CellId → PullSignalData` lookup.
///
/// `cell_id` and `durability` allow `commit_batch` and
/// `recompute_batch_max_durability` to read signal metadata directly from
/// the trait object rather than going back to the SoA array.
trait Committable {
  do_commit(Self) -> Bool
  cell_id(Self) -> CellId
  durability(Self) -> Durability
  fire_on_change_if_set(Self) -> Unit
}
```

**Step 4: Implement Committable on PullSignalData**

Remove `rollback_pending` field from `PullSignalData` in `cells/pull_signal.mbt` (it is dead code — set but never called), then append the impl:

```moonbit
// BEFORE (remove rollback_pending field from the struct):
priv struct PullSignalData {
  cell_id : CellId
  label : String?
  mut changed_at : Revision
  mut durability : Durability
  subscribers : @hashset.HashSet[CellId]
  mut on_change : (() -> Unit)?
  mut commit_pending : (() -> Bool)?
  // rollback_pending removed — it was set but never invoked
}
```

```moonbit
///|
/// Committable dispatch for pull-signal cells.
impl Committable for PullSignalData {
  fn do_commit(self) -> Bool {
    match self.commit_pending {
      Some(f) => {
        let changed = f()
        self.commit_pending = None
        changed
      }
      None => false
    }
  }

  fn cell_id(self) -> CellId { self.cell_id }

  fn durability(self) -> Durability { self.durability }

  fn fire_on_change_if_set(self) -> Unit {
    match self.on_change {
      Some(f) => f()
      None => ()
    }
  }
}
```

**Step 5: Remove rollback_pending references in signal.mbt**

In `cells/signal.mbt`, remove `rollback_pending` from every reference:
1. In `set_batch` (~line 221): remove `sig_data.rollback_pending = Some(...)` line
2. In `set_batch` rollback closure (~line 221): remove `sig_data.rollback_pending = None` line
3. In `set_batch_unconditional` (~line 241): same two removals

After the removals, `set_batch` registers commit like this (the only remaining closure):
```moonbit
if sig_data.commit_pending is None {
  sig_data.commit_pending = Some(() => self.commit())
  self.rt.record_batch_signal(self.cell_id)
}
```

**Step 6: Run moon check**

```bash
moon check
```

Expected: OK. (Any remaining `rollback_pending` references will be caught here.)

**Step 7: Run all tests**

```bash
moon test
```

Expected: all tests pass.

**Step 8: Commit**

```bash
git add cells/cell_ops.mbt cells/pull_signal.mbt cells/signal.mbt cells/committable_wbtest.mbt
git commit -m "feat(committable): define Committable trait, implement on PullSignalData, remove dead rollback_pending"
```

---

### Task 7: Replace batch_pending_signals with batch_pending : Array[&Committable]

**Files:**
- Modify: `cells/runtime.mbt`
- Modify: `cells/signal.mbt`

**Background:** The `batch_pending_signals : Array[CellId]` array stores signal IDs so `commit_batch` can call `get_pull_signal(id)` then invoke `commit_pending`. With `batch_pending : Array[&Committable]`, we store the `PullSignalData` reference directly as a trait object — no `CellId` lookup in `commit_batch`. `remove_batch_signal` (called from rollback closures) needs `CellId` to find the entry; it uses `c.cell_id()` on the trait object.

**Step 1: Add batch_pending field to Runtime struct, remove batch_pending_signals**

In `cells/runtime.mbt`, replace the `batch_pending_signals` field:

```moonbit
pub(all) struct Runtime {
  priv runtime_id : Int
  priv mut current_revision : Revision
  priv mut next_cell_id : Int
  priv tracking_stack : Array[ActiveQuery]
  priv durability_last_changed : FixedArray[Revision]
  priv mut batch_depth : Int
  priv batch_pending : Array[&Committable]    // replaces batch_pending_signals
  priv batch_frames : Array[BatchFrame]
  priv mut batch_max_durability : Durability
  priv mut on_change : (() -> Unit)?
  // SoA storage arrays
  priv pull_signals : Array[PullSignalData]
  priv pull_memos : Array[PullMemoData]
  priv cell_index : Array[CellRef]
  priv cell_ops : Array[&CellOps]

  fn new(on_change? : () -> Unit) -> Runtime
}
```

Update `Runtime::new` initializer: change `batch_pending_signals: []` to `batch_pending: []`.

**Step 2: Rewrite record_batch_signal to accept &Committable**

Rename `record_batch_signal(cell_id : CellId)` to `record_batch_signal(committable : &Committable)`:

```moonbit
fn Runtime::record_batch_signal(
  self : Runtime,
  committable : &Committable,
) -> Unit {
  self.batch_pending.push(committable)
}
```

**Step 3: Rewrite remove_batch_signal to use cell_id() on Committable**

```moonbit
fn Runtime::remove_batch_signal(self : Runtime, cell_id : CellId) -> Unit {
  let kept : Array[&Committable] = []
  let mut removed = false
  for c in self.batch_pending {
    if not(removed) && c.cell_id() == cell_id {
      removed = true
    } else {
      kept.push(c)
    }
  }
  self.batch_pending.clear()
  for c in kept {
    self.batch_pending.push(c)
  }
}
```

**Step 4: Rewrite recompute_batch_max_durability**

```moonbit
fn Runtime::recompute_batch_max_durability(self : Runtime) -> Unit {
  let mut max_durability : Durability = Low
  for c in self.batch_pending {
    let d = c.durability()
    if d > max_durability {
      max_durability = d
    }
  }
  self.batch_max_durability = max_durability
}
```

**Step 5: Rewrite commit_batch to dispatch through Committable**

Replace `commit_batch` with the following. Key changes:
- Loop over `batch_pending` instead of `batch_pending_signals`
- Call `c.do_commit()` directly (no `get_pull_signal`)
- Call `c.fire_on_change_if_set()` for callback dispatch
- `mark_input_changed(c.cell_id())` still needed for SoA `changed_at` update

```moonbit
fn Runtime::commit_batch(self : Runtime) -> Unit {
  let mut any_changed = false
  while self.batch_pending.length() > 0 {
    // Phase 1: commit pending values and collect which actually changed
    let changed : Array[&Committable] = []
    for c in self.batch_pending {
      if c.do_commit() {
        changed.push(c)
      }
    }
    self.batch_pending.clear()
    // Phase 2: if any value actually changed, do a single revision bump
    if changed.length() > 0 {
      any_changed = true
      self.advance_revision(self.batch_max_durability)
      // Sweep changed signals: update changed_at and collect callbacks.
      let callbacks : Array[() -> Unit] = []
      for c in changed {
        // Update changed_at on the SoA entry
        let sig = self.mark_input_changed(c.cell_id())
        ignore(sig)
        // Collect on_change callback (if any) via Committable
        let c_copy = c
        callbacks.push(() => c_copy.fire_on_change_if_set())
      }
      self.batch_max_durability = Low
      // Raise batch_depth while invoking callbacks so signal.set() inside
      // a callback takes the batch path and doesn't re-entrantly fire_on_change.
      self.batch_depth = self.batch_depth + 1
      for cb in callbacks {
        cb()
      }
      self.batch_depth = self.batch_depth - 1
    } else {
      self.batch_max_durability = Low
    }
  }
  self.batch_max_durability = Low
  if any_changed {
    self.fire_on_change()
  }
}
```

> Note: `mark_input_changed` is still called to update `changed_at` on the `PullSignalData`. This is one remaining SoA lookup per changed signal per batch. A future optimization would add `set_changed_at_to_current(Runtime)` to `Committable` to eliminate it, but that requires passing `Runtime` through the trait (not object-safe as a method). For now, this is acceptable.

**Step 6: Update signal.mbt to pass &Committable to record_batch_signal**

In `Signal::set_batch` and `Signal::set_batch_unconditional`, change the registration line from:
```moonbit
self.rt.record_batch_signal(self.cell_id)
```
to:
```moonbit
let sig_committable : &Committable = sig_data
self.rt.record_batch_signal(sig_committable)
```

**Step 7: Run moon check**

```bash
moon check
```

Expected: OK. Fix any remaining references to `batch_pending_signals`.

**Step 8: Run all tests**

```bash
moon test
```

Expected: all tests pass.

**Step 9: Update the wbtest**

Update `cells/committable_wbtest.mbt` to not access `batch_depth` directly (it's internal). Replace with a full batch round-trip test:

```moonbit
///|
test "committable: batch commit updates signal value" {
  let rt = Runtime::new()
  let sig = Signal::new(rt, 1)
  rt.batch(() => { sig.set(2) })
  inspect(sig.get(), content="2")
}

///|
test "committable: batch with no-op set does not bump revision" {
  let rt = Runtime::new()
  let sig = Signal::new(rt, 1)
  let before = rt.current_revision
  rt.batch(() => { sig.set(1) })  // same value
  inspect(rt.current_revision == before, content="true")
}

///|
test "committable: on_change fires via Committable after batch" {
  let rt = Runtime::new()
  let sig = Signal::new(rt, 1)
  let mut fired = false
  sig.on_change(fn(_v) { fired = true })
  rt.batch(() => { sig.set(2) })
  inspect(fired, content="true")
}
```

**Step 10: Run tests again**

```bash
moon test
```

Expected: all tests pass including the new committable tests.

**Step 11: Commit**

```bash
git add cells/runtime.mbt cells/signal.mbt cells/committable_wbtest.mbt
git commit -m "refactor(committable): replace batch_pending_signals with Array[&Committable], simplify commit_batch"
```

---

### Final: Run the full test suite and verify

```bash
moon test
```

Expected: all tests pass.

```bash
moon check
```

Expected: no warnings or errors.

---

### Note on future optimization

The current `Committable` impl on `PullSignalData` still allocates `commit_pending : () -> Bool` closures per `set()` call during batches. A follow-up could implement `Committable` directly on `Signal[T: Eq]` — `do_commit` would access `self.pending_value` directly without any closure — and move `on_change` from `PullSignalData` to `Signal[T]` to eliminate the `mark_input_changed` SoA lookup in `commit_batch`. That change is non-trivial (requires two `Committable` impls for Eq vs unconditional, one of which needs a thin wrapper struct) and is not needed for Phase 3 correctness.
