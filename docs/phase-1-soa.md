# Phase 1: SoA Storage Refactor

**Reference**: `docs/incr-unified-design.md` §2–3.1–3.2, §4.1, §8

## Goal

Replace the current single `Array[CellMeta]` storage with separate typed arrays for pull signals and pull memos. This is a pure internal refactor — zero public API changes, zero behavior changes. All 200 existing tests must pass at the end.

## Starting State

The current implementation stores all cell metadata in `Runtime.cells : Array[CellMeta]` where each element is type-erased via closures. `CellId.id` is a direct index into this array. `Signal[T]` and `Memo[T]` hold `CellId` values and do their work via `Runtime` method calls.

## Deliverables

| File | Action |
|------|--------|
| `cells/cell_ref.mbt` | **Create** — `CellRef` enum (Phase 1 variants only) |
| `cells/runtime.mbt` | **Adapt** — replace `cells` array with SoA; update `alloc_cell_id` |
| `cells/signal.mbt` | **Adapt** — use `PullSignalData`; keep `Signal[T]` API identical |
| `cells/memo.mbt` | **Adapt** — use `PullMemoData`; keep `Memo[T]` API identical |
| `cells/verify.mbt` | **Adapt** — replace `maybe_changed_after` recursion with explicit `VerifyFrame` stack |

## Step 1: Add `CellRef` (Phase 1 variants only)

Create `cells/cell_ref.mbt`. Include only the variants needed for Phase 1; remaining variants (`PushReactive`, `PushEffect`, `Relation`, `Rule`, `Disposed`) are added in later phases.

```moonbit
pub enum CellRef {
  PullSignal(index : Int)
  PullMemo(index : Int)
}
```

> **Note**: `get_changed_at`, `ensure_up_to_date`, `get_subscribers` will need wildcard arms (`_ => ...`) to compile against this partial enum until later phases fill them in.

## Step 2: Add `PullSignalData` and `PullMemoData`

These replace `CellMeta` for pull cells. Key differences from `CellMeta`:

- Value (`Ref[T]`) stays in the `Signal[T]` / `Memo[T]` handle — not in the data struct
- `cell_id : CellId` is stored as the first field (enables reverse lookup)
- `subscribers` field present but unused until Phase 2
- `commit_pending` / `rollback_pending` closures replace the old `commit_pending` closure on `CellMeta`

```moonbit
struct PullSignalData {
  cell_id : CellId
  label : String?
  mut changed_at : Revision
  mut durability : Durability
  subscribers : @hashset.HashSet[CellId]   // populated in Phase 2
  mut on_change : (() -> Unit)?
  mut commit_pending   : (() -> Bool)?
  mut rollback_pending : (() -> Unit)?
}

struct PullMemoData {
  cell_id : CellId
  label : String?
  compute : () -> Result[Bool, CycleError]
  mut changed_at : Revision
  mut verified_at : Revision
  mut durability : Durability
  mut dependencies : Array[CellId]
  subscribers : @hashset.HashSet[CellId]   // populated in Phase 2
  mut in_progress : Bool
  mut on_change : (() -> Unit)?
}
```

`compute` is a type-erased closure created at `Memo[T]` construction time. It:
1. Calls `begin_tracking` / runs user fn / calls `end_tracking` + `finish_tracking` (Phase 2 adds tracking; in Phase 1, tracking can remain as-is)
2. Compares new value with cached value
3. Updates cached value if different; backdates `changed_at` if equal (existing backdating logic)
4. Fires `on_change` if value changed
5. Returns `Ok(true)` if changed, `Ok(false)` if unchanged, `Err(CycleError)` on cycle

## Step 3: Update `Runtime` struct

Replace `cells : Array[CellMeta]` with:

```
Runtime
├── pull_signals   : Array[PullSignalData]
├── pull_memos     : Array[PullMemoData]
├── cell_index     : Array[CellRef]          // CellId.id → CellRef
├── (all other existing fields unchanged)
```

Remove `cells` entirely. Keep all other Runtime fields unchanged.

## Step 4: Update `alloc_cell_id`

The existing `alloc_cell_id` appended to `cells`. Replace with:

```moonbit
fn Runtime::alloc_cell_id(self, cell_ref : CellRef) -> CellId {
  let id = self.next_cell_id
  self.next_cell_id += 1
  self.cell_index.push(cell_ref)  // cell_index[id] = cell_ref
  { runtime_id: self.runtime_id, id }
}
```

Signal allocation pattern:

```moonbit
fn Runtime::new_signal_id[T : Eq](self, initial : T) -> SignalId[T] {
  let idx = self.pull_signals.length()
  let cell_id = self.alloc_cell_id(CellRef::PullSignal(idx))
  self.pull_signals.push(PullSignalData {
    cell_id,
    label: None,
    changed_at: self.revision,
    durability: Durability::Low,
    subscribers: @hashset.new(),
    on_change: None,
    commit_pending: None,
    rollback_pending: None,
  })
  SignalId { id: cell_id }
}
```

Memo allocation: same pattern with `PullMemo(idx)` and `PullMemoData`.

## Step 5: Add `SignalId[T]` and `MemoId[T]` newtype handles

These are internal handles used by Runtime methods for typed dispatch. They are **not** the public API — `Signal[T]` and `Memo[T]` remain the public-facing structs unchanged.

```moonbit
pub struct SignalId[T] { id : CellId }
pub struct MemoId[T]   { id : CellId }
```

## Step 6: Replace `maybe_changed_after` with `pull_verify` (explicit stack)

The current recursive `maybe_changed_after` will overflow on deep dependency graphs. Replace it with an explicit `VerifyFrame` stack. The behavior is identical; only the implementation strategy changes.

```moonbit
struct VerifyFrame {
  cell_id    : CellId
  memo_idx   : Int
  mut dep_cursor : Int
  mut changed    : Bool
}

fn Runtime::pull_verify(self, cell_id : CellId) -> Result[Unit, CycleError] {
  match self.cell_index[cell_id.id] {
    PullSignal(_) => Ok(())
    PullMemo(root_idx) => {
      let root = self.pull_memos[root_idx]
      if root.verified_at >= self.revision { return Ok(()) }
      if root.in_progress {
        return Err(CycleError::from_path(self.collect_in_progress_path(), cell_id))
      }
      let stack : Array[VerifyFrame] = []
      root.in_progress = true
      stack.push({ cell_id, memo_idx: root_idx, dep_cursor: 0, changed: false })
      let mut err : CycleError? = None
      while not(stack.is_empty()) && err == None {
        let top = stack.length() - 1
        let memo = self.pull_memos[stack[top].memo_idx]
        if stack[top].dep_cursor < memo.dependencies.length() {
          let dep_id = memo.dependencies[stack[top].dep_cursor]
          stack[top].dep_cursor += 1
          match self.cell_index[dep_id.id] {
            PullMemo(dep_idx) => {
              let dep = self.pull_memos[dep_idx]
              if dep.verified_at < self.revision {
                if dep.in_progress {
                  err = Some(CycleError::from_path(self.collect_in_progress_path(), dep_id))
                } else {
                  dep.in_progress = true
                  stack.push({ cell_id: dep_id, memo_idx: dep_idx, dep_cursor: 0, changed: false })
                }
              } else {
                if dep.changed_at > memo.verified_at { stack[top].changed = true }
              }
            }
            _ => {
              if self.get_changed_at(dep_id) > memo.verified_at { stack[top].changed = true }
            }
          }
        } else {
          let frame = stack.pop().unwrap()
          memo.in_progress = false
          if frame.changed {
            // Two-level structure:
            //   pull_verify stack = VERIFICATION WALK (decides whether to recompute)
            //   compute()         = RECOMPUTATION (handles its own tracking internally)
            // All deps are verified before compute fires, so nested get() calls
            // inside compute() return immediately without re-entering pull_verify.
            match (memo.compute)() {
              Ok(_) => ()
              Err(e) => { err = Some(e) }
            }
          }
          memo.verified_at = self.revision
          if not(stack.is_empty()) {
            let parent_top = stack.length() - 1
            let parent_verified_at = self.pull_memos[stack[parent_top].memo_idx].verified_at
            if memo.changed_at > parent_verified_at { stack[parent_top].changed = true }
          }
        }
      }
      for frame in stack { self.pull_memos[frame.memo_idx].in_progress = false }
      match err { Some(e) => Err(e); None => Ok(()) }
    }
  }
}

fn Runtime::collect_in_progress_path(self) -> Array[CellId] {
  let path : Array[CellId] = []
  for memo in self.pull_memos {
    if memo.in_progress { path.push(memo.cell_id) }
  }
  path
}
```

## Step 7: Update `cell_id_for` and `get_changed_at`

```moonbit
fn Runtime::cell_id_for(self, cell_ref : CellRef) -> CellId {
  match cell_ref {
    PullSignal(idx) => self.pull_signals[idx].cell_id
    PullMemo(idx)   => self.pull_memos[idx].cell_id
  }
}

fn Runtime::get_changed_at(self, cell_id : CellId) -> Revision {
  match self.cell_index[cell_id.id] {
    PullSignal(idx) => self.pull_signals[idx].changed_at
    PullMemo(idx)   => self.pull_memos[idx].changed_at
  }
}
```

## Step 8: Update batch commit mechanics

`commit_pending_signals()` iterates `batch_pending_signals`, calls each signal's `commit_pending` closure, and returns the CellIds where `commit_pending()` returned `true`:

```moonbit
fn Runtime::commit_pending_signals(self) -> Array[CellId] {
  let changed = []
  for cell_id in self.batch_pending_signals {
    match self.cell_index[cell_id.id] {
      PullSignal(idx) => {
        match self.pull_signals[idx].commit_pending {
          Some(f) => if f() { changed.push(cell_id) }
          None => ()
        }
        self.pull_signals[idx].commit_pending = None
        self.pull_signals[idx].rollback_pending = None
      }
      _ => ()
    }
  }
  changed
}
```

`advance_revision`:
```moonbit
fn Runtime::advance_revision(self, durability : Durability) -> Unit {
  self.revision = Revision(self.revision.val + 1)
  for d in Durability::all() {
    if d <= durability {
      self.durability_last_changed[d.index()] = self.revision
    }
  }
}
```

## Definition of Done

- `moon test` passes all 200 existing tests with no changes
- `moon check` has no type errors
- No `cells` or `CellMeta` references remain in the codebase (all replaced by SoA)
- `maybe_changed_after` is gone; `pull_verify` with explicit stack is in its place
