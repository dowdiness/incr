# Phase 5: Hybrid Mode (Push-Dirty + Pull-Verify)

**Reference**: `docs/incr-unified-design.md` §10 Phase 5

## Goal

Add `HybridMemo[T]`: a memo that receives dirty flags eagerly (like push) but verifies lazily on `get()` (like pull). This is an optimization of pull mode — it skips the full dependency walk when the cell hasn't been dirtied.

## Starting State

Phase 2 (subscriber links) and Phase 3 (push reactives) are both complete. `commit_batch` already calls `push_propagate_from`; this phase extends dirty-flag propagation to cover HybridMemo nodes.

## Known Design Gap to Resolve First

`commit_batch` currently calls `enqueue_push_subscribers` (inside `push_propagate_from`) which only enqueues `PushReactive` and `PushEffect` nodes. A `HybridMemo` subscribed to a `PullSignal` would never receive a dirty flag, defeating the optimization.

**Decision required before implementing this phase**: choose one of:

**Option A — Add `HybridMemo` case to `enqueue_push_subscribers`**
Mark the hybrid memo dirty and add it to a separate flat dirty set (not the level-sorted queue — hybrid memos don't recompute eagerly, they just set a flag). In `commit_batch`, after `push_propagate_from`, drain the hybrid-memo dirty set.

**Option B — Separate dirty-marking pass over pull-signal subscribers**
After `push_propagate_from` returns, walk the subscribers of each changed signal a second time, and mark any `HybridMemo` cells dirty. This is simpler but does two traversals.

Option A is recommended. It keeps hybrid memos out of the push queue (they don't execute eagerly) while still receiving dirty flags from pull-signal changes.

**Resolve this gap before writing code.** The rest of this plan assumes Option A.

## Deliverables

| File | Action |
|------|--------|
| `cells/hybrid_memo.mbt` | **Create** — `HybridMemoData`, `HybridMemoId[T]`, `HybridMemo[T]` |
| `cells/cell_ref.mbt` | **Adapt** — add `HybridMemo` variant |
| `cells/propagate.mbt` | **Adapt** — `enqueue_push_subscribers` adds `HybridMemo` dirty-flag case |
| `cells/runtime.mbt` | **Adapt** — `commit_batch` drains hybrid dirty set; update helpers |
| `cells/verify.mbt` | **Adapt** — `pull_verify` handles `HybridMemo` variant |

## Step 1: Add `HybridMemo` to `CellRef`

```moonbit
pub enum CellRef {
  PullSignal(index : Int)
  PullMemo(index : Int)
  PushReactive(index : Int)
  PushEffect(index : Int)
  Disposed
  Relation(index : Int)
  Rule(index : Int)
  HybridMemo(index : Int)   // new
}
```

## Step 2: `HybridMemoData`

```moonbit
struct HybridMemoData {
  cell_id : CellId
  label : String?
  compute : () -> Result[Bool, CycleError]  // same contract as PullMemoData.compute
  mut changed_at : Revision
  mut verified_at : Revision
  mut durability : Durability
  mut dependencies : Array[CellId]
  subscribers : @hashset.HashSet[CellId]
  mut in_progress : Bool
  mut dirty : Bool              // set true by push dirty-flag propagation
  mut on_change : (() -> Unit)?
}
```

The only addition vs `PullMemoData` is `dirty : Bool`.

## Step 3: Implement `HybridMemo::get`

```moonbit
pub fn HybridMemo::get(self) -> T {
  match self.rt.cell_index[self.id.id] {
    HybridMemo(idx) => {
      let h = self.rt.hybrid_memos[idx]
      if not(h.dirty) && h.verified_at >= self.rt.revision {
        // Fast path: not dirtied and already verified this revision
        return self.value_ref.val.unwrap()
      }
      // Slow path: dirty or stale — fall through to pull verification
      self.rt.pull_verify_hybrid(self.id.id) |> ignore
      h.dirty = false
      self.value_ref.val.unwrap()
    }
    _ => abort("HybridMemo::get: invalid cell kind")
  }
}
```

`pull_verify_hybrid` reuses `pull_verify` logic but dispatches on `HybridMemo` instead of `PullMemo`. Alternatively, unify by making `pull_verify` handle both via a common interface.

## Step 4: Dirty-flag propagation (Option A)

Add a `hybrid_dirty : Array[CellId]` list to Runtime (or use a `HashSet[Int]` of HybridMemo indices for O(1) deduplication).

In `enqueue_push_subscribers` (inside `propagate.mbt`):

```moonbit
HybridMemo(i) => {
  if not(self.hybrid_memos[i].dirty) {
    self.hybrid_memos[i].dirty = true
    self.hybrid_dirty.push(sub_id)  // track for commit_batch cleanup
  }
}
```

After `push_propagate_from` returns in `commit_batch`, the `hybrid_dirty` list is already populated. No second traversal needed — the dirty flags were set during propagation.

`hybrid_dirty` is cleared at the start of each `commit_batch` (same as `batch_pending_signals`).

## Step 5: Update `pull_verify` to handle `HybridMemo`

```moonbit
// In ensure_up_to_date — add:
HybridMemo(_) => self.pull_verify(cell_id)

// In pull_verify, the stack currently only pushes PullMemo frames.
// Extend to also push HybridMemo frames with the same VerifyFrame struct.
// The only difference: check h.dirty || h.verified_at < self.revision
// as the trigger, rather than just verified_at < self.revision.
```

## Step 6: Update all helpers

```moonbit
// get_subscribers — add:
HybridMemo(idx) => self.hybrid_memos[idx].subscribers.iter()

// get_subscribers_mut — add:
HybridMemo(idx) => self.hybrid_memos[idx].subscribers

// get_changed_at — add:
HybridMemo(idx) => self.hybrid_memos[idx].changed_at

// cell_id_for — add:
HybridMemo(idx) => self.hybrid_memos[idx].cell_id
```

## Tests

```moonbit
test "hybrid memo: fast path when not dirtied" {
  // Signal changes but hybrid memo not in dependency chain → dirty = false
  // get() returns cached without calling compute
  let mut compute_count = 0
  let rt = Runtime::new()
  let s = Signal(rt, 1)
  let unrelated = Signal(rt, 99)
  let h = HybridMemo(rt, fn() { compute_count += 1; s.get() })
  let _ = h.get()
  inspect(compute_count, content="1")
  unrelated.set(100)
  let _ = h.get()
  inspect(compute_count, content="1")  // not recomputed
}

test "hybrid memo: dirty flag triggers recompute" {
  let rt = Runtime::new()
  let s = Signal(rt, 1)
  let h = HybridMemo(rt, fn() { s.get() * 2 })
  inspect(h.get(), content="2")
  s.set(5)
  inspect(h.get(), content="10")
}

test "hybrid memo: pull-signal change sets dirty flag via push propagation" {
  // After s.set(), h.dirty should be true before h.get() is called
  let rt = Runtime::new()
  let s = Signal(rt, 1)
  let h = HybridMemo(rt, fn() { s.get() })
  let _ = h.get()
  s.set(2)
  let h_idx = match rt.cell_index[h.id.id] { HybridMemo(i) => i; _ => abort("") }
  inspect(rt.hybrid_memos[h_idx].dirty, content="true")
}

test "hybrid memo: backdating — unchanged value clears dirty without bumping changed_at" {
  let rt = Runtime::new()
  let s = Signal(rt, 1)
  let h = HybridMemo(rt, fn() { s.get() })  // always returns same value
  let _ = h.get()
  let changed_at_before = rt.hybrid_memos[...].changed_at
  s.set(1)  // same value → signal backdating → h may not be dirtied
  let _ = h.get()
  inspect(rt.hybrid_memos[...].changed_at == changed_at_before, content="true")
}
```

## Definition of Done

- All Phase 1 + Phase 2 + Phase 3 tests pass
- All Phase 5 tests listed above pass
- `moon check` has no type errors
- Fast path test confirms `compute` is not called when `dirty = false`
- Dirty flag is set by push propagation before `get()` is called
- `pull_verify` correctly handles `HybridMemo` frames on the explicit stack
