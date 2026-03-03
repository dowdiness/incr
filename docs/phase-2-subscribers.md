# Phase 2: Subscriber Links

**Reference**: `docs/incr-unified-design.md` §5

## Goal

Add bidirectional subscriber tracking to pull cells. After this phase, every dependency edge `A → B` ("A reads B") is mirrored by a reverse subscriber edge `B → A` ("B has subscriber A"). The edges are maintained incrementally by `finish_tracking` after each recompute.

This phase is a pure infrastructure addition — no behavior changes, no new cell kinds. Subscriber links are populated but not yet used for push propagation (that is Phase 3).

## Starting State

Phase 1 is complete. `PullSignalData` and `PullMemoData` both already have a `subscribers : @hashset.HashSet[CellId]` field — it just isn't populated yet. The dependency list (`PullMemoData.dependencies`) is still maintained by the existing tracking mechanism.

## Deliverables

| File | Action |
|------|--------|
| `cells/tracking.mbt` | **Adapt** — add `begin_tracking`, `end_tracking` helpers |
| `cells/runtime.mbt` | **Adapt** — add `finish_tracking`, `get_subscribers`, `get_subscribers_mut` |
| `cells/memo.mbt` | **Adapt** — `compute` closure calls `begin_tracking`/`end_tracking`/`finish_tracking` |

## Step 1: Add `begin_tracking` and `end_tracking`

These replace any ad-hoc tracking frame push/pop currently in the codebase. The names deliberately avoid "push"/"pop" to prevent confusion with the push-propagation queue (Phase 3).

```moonbit
fn Runtime::begin_tracking(self, cell_id : CellId) -> Unit {
  self.tracking_stack.push(ActiveQuery::new(cell_id))
}

fn Runtime::end_tracking(self) -> Array[CellId] {
  // deps_array() converts the internal HashSet[CellId] to Array[CellId]
  self.tracking_stack.pop().unwrap().deps_array()
}
```

## Step 2: Add `finish_tracking`

Called after every `compute()` to diff old vs new dependencies and update subscriber links. O(|old| + |new|) via HashSet membership.

```moonbit
fn Runtime::finish_tracking(
  self,
  cell_id  : CellId,
  old_deps : Array[CellId],
  new_deps : Array[CellId],
) -> Unit {
  let new_set : @hashset.HashSet[CellId] = @hashset.from_iter(new_deps.iter())
  let old_set : @hashset.HashSet[CellId] = @hashset.from_iter(old_deps.iter())
  // Remove self from deps no longer read
  for dep in old_deps {
    if not(new_set.contains(dep)) {
      self.get_subscribers_mut(dep).remove(cell_id)
    }
  }
  // Add self to newly read deps
  for dep in new_deps {
    if not(old_set.contains(dep)) {
      self.get_subscribers_mut(dep).insert(cell_id)
    }
  }
}
```

## Step 3: Add `get_subscribers` and `get_subscribers_mut`

Phase 2 only has `PullSignal` and `PullMemo` variants. Later phases add arms for `PushReactive`, `Relation`, etc. Add wildcard arms now to stay compile-clean:

```moonbit
fn Runtime::get_subscribers(self, cell_ref : CellRef) -> Iter[CellId] {
  match cell_ref {
    PullSignal(idx) => self.pull_signals[idx].subscribers.iter()
    PullMemo(idx)   => self.pull_memos[idx].subscribers.iter()
    // Phase 3+ will add PushReactive, PushEffect, Relation arms
    _ => Iter::empty()
  }
}

fn Runtime::get_subscribers_mut(self, cell_id : CellId) -> @hashset.HashSet[CellId] {
  match self.cell_index[cell_id.id] {
    PullSignal(idx) => self.pull_signals[idx].subscribers
    PullMemo(idx)   => self.pull_memos[idx].subscribers
    _ => abort("get_subscribers_mut: cell kind has no subscribers field")
  }
}
```

## Step 4: Update `compute` closure construction in `Memo[T]`

The `compute` closure stored in `PullMemoData` must now call the tracking helpers. Adapt the closure created inside `Memo[T]::new()` / `Runtime::new_memo_id`:

```moonbit
// Inside new_memo_id[T : Eq](self, compute_fn : () -> T) -> MemoId[T]:
let memo_ref : Ref[T?] = Ref(None)   // cached value (None = uninitialized)
let old_deps_ref : Ref[Array[CellId]] = Ref([])

let compute : () -> Result[Bool, CycleError] = fn() {
  self.begin_tracking(cell_id)
  let new_val = compute_fn()   // user's function; may call get() on other cells
  let new_deps = self.end_tracking()
  self.finish_tracking(cell_id, old_deps_ref.val, new_deps)
  old_deps_ref.val = new_deps
  // Update PullMemoData.dependencies to match (for pull_verify dep walk)
  self.pull_memos[idx].dependencies = new_deps

  let changed = match memo_ref.val {
    None => true                          // first compute
    Some(prev) => prev != new_val         // changed?
  }
  if changed {
    memo_ref.val = Some(new_val)
    // changed_at left at current revision (set by caller pull_verify)
    match self.pull_memos[idx].on_change {
      Some(f) => f()
      None => ()
    }
    Ok(true)
  } else {
    // Backdating: value unchanged, so changed_at stays at old value
    Ok(false)
  }
}
```

> **Note**: `cell_id` and `idx` are captured from the outer `new_memo_id` scope. `memo_ref` holds the typed cached value; it is NOT stored in `PullMemoData`.

## Step 5: (Optional) Verify GC-readiness

After this phase, a cell's `subscribers` set being empty and its handle being unreachable means it can be freed. You don't need to implement GC now, but verify the links are correct: after `finish_tracking`, every dep of a live memo should appear in that dep's `subscribers` set with the memo's CellId.

Add a debug helper (test-only) that asserts subscriber/dependency consistency:

```moonbit
// test helper
fn Runtime::assert_subscriber_consistency(self) -> Unit {
  for i, memo in self.pull_memos {
    for dep_id in memo.dependencies {
      let subs = self.get_subscribers(self.cell_index[dep_id.id])
      assert(subs.contains(memo.cell_id))
    }
  }
}
```

## Tests

All 200 existing tests must still pass. Add:

```moonbit
test "subscriber links populated after memo read" {
  let rt = Runtime::new()
  let s = Signal(rt, 1)
  let m = Memo(rt, fn() { s.get() })
  let _ = m.get()
  // s's subscribers should contain m's cell_id
  let s_idx = match rt.cell_index[s.id.id] { PullSignal(i) => i; _ => abort("") }
  inspect(rt.pull_signals[s_idx].subscribers.contains(m.id.id), content="true")
}

test "subscriber links updated on dynamic dep change" {
  let rt = Runtime::new()
  let flag = Signal(rt, true)
  let a = Signal(rt, 1)
  let b = Signal(rt, 2)
  let m = Memo(rt, fn() { if flag.get() { a.get() } else { b.get() } })
  let _ = m.get()
  // m depends on flag and a; b should NOT be in m's deps
  let m_idx = match rt.cell_index[m.id.id] { PullMemo(i) => i; _ => abort("") }
  inspect(rt.pull_memos[m_idx].dependencies.length(), content="2")  // flag, a
  flag.set(false)
  let _ = m.get()
  // now m depends on flag and b; a should be removed from subscribers
  let a_idx = match rt.cell_index[a.id.id] { PullSignal(i) => i; _ => abort("") }
  inspect(rt.pull_signals[a_idx].subscribers.contains(m.id.id), content="false")
}
```

## Definition of Done

- All 200 existing tests pass
- `moon check` has no type errors
- After any `memo.get()` call, the memo's `cell_id` appears in every dependency's `subscribers` set
- After a memo's dependency set changes (dynamic deps), stale subscriber links are removed
