# Hybrid Dirty-Marking Separation Implementation Plan

**Status:** Complete

> **For Claude:** REQUIRED SUB-SKILL: Use superpowers:executing-plans to implement this plan task-by-task.

**Goal:** Separate hybrid memo dirty-marking from push propagation to eliminate priority queue overhead when only hybrid memos are downstream of a signal.

**Outcome:** The plan's approach (separate dirty walk) was superseded by the discovery that dirty-marking itself is unnecessary — `verified_at` staleness detection handles all cases. HybridMemo no longer increments `node_count`, so `signal.set()` skips `push_propagate_from` entirely when only hybrid memos are downstream. Hybrid stale benchmark dropped from 0.36µs to 0.30µs, matching memo stale (0.28µs).

**Architecture:** Currently `HybridMemo::new` increments `push.node_count`, which causes every `Signal::set` to call `push_propagate_from` (allocates a PriorityQueue, runs BFS). We split this into two gates: `hybrid_memo_count` for a lightweight dirty-flag walk, and `node_count` for the full push propagation (reactives + effects only). The dirty-flag walk is a simple BFS through subscriber links — no queue, no level sorting.

**Tech Stack:** MoonBit, moon CLI (check/test/bench)

---

## Dependency Graph

```
Task 1 (add hybrid_memo_count + mark_hybrid_dirty)
  └── Task 2 (wire up all call sites)
        └── Task 3 (update tests + benchmarks)
              └── Task 4 (cleanup)
```

---

### Task 1: Add `hybrid_memo_count` field and `mark_hybrid_dirty` function

These must be done together — the new field is referenced by the new function.

**Files:**
- Modify: `cells/runtime.mbt:66-75` (PushState struct + Runtime::new initializer)
- Modify: `cells/push_propagate.mbt` (add `mark_hybrid_dirty` function)

**Step 1: Add `hybrid_memo_count` to `PushState`**

In `cells/runtime.mbt`, add `mut hybrid_memo_count : Int` to `PushState` struct after line 73 (`mut node_count : Int`). Update the comment on `node_count` to say "reactives + effects only". Initialize to `0` in `Runtime::new` (line 164).

```moonbit
priv struct PushState {
  reactives : Array[PushReactiveData]
  effects : Array[PushEffectData]
  free_reactives : Array[Int]
  free_effects : Array[Int]
  /// Count of live push cells (reactives + effects only).
  /// Used as an O(1) gate before push propagation.
  mut node_count : Int
  /// Count of live hybrid memos. Used as an O(1) gate before
  /// the lightweight dirty-marking walk.
  mut hybrid_memo_count : Int
  hybrid_dirty : Array[CellId]
}
```

And in `Runtime::new` initializer:
```moonbit
push: {
  reactives: [],
  effects: [],
  free_reactives: [],
  free_effects: [],
  node_count: 0,
  hybrid_memo_count: 0,
  hybrid_dirty: [],
},
```

**Step 2: Add `mark_hybrid_dirty` to `push_propagate.mbt`**

Add this function at the top of `cells/push_propagate.mbt` (before `PushEntry` struct):

```moonbit
///|
/// Lightweight dirty-marking walk for hybrid memos.
///
/// BFS through subscriber links from changed sources. Marks HybridMemo
/// dirty flags and bridges through PullMemo/HybridMemo to reach
/// transitive hybrid dependents. No priority queue, no level sorting.
fn Runtime::mark_hybrid_dirty(
  self : Runtime,
  changed_sources : Array[CellId],
) -> Unit {
  let worklist : Array[CellId] = []
  for source_id in changed_sources {
    worklist.push(source_id)
  }
  let mut wi = 0
  while wi < worklist.length() {
    let id = worklist[wi]
    wi += 1
    for sub_id in self.get_subscribers(id) {
      match self.core.cell_index[sub_id.id] {
        HybridMemo(i) => {
          if not(self.pull.memos[i].dirty) {
            self.pull.memos[i].dirty = true
            self.push.hybrid_dirty.push(sub_id)
          }
          worklist.push(sub_id)
        }
        PullMemo(_) => worklist.push(sub_id)
        _ => ()
      }
    }
  }
}
```

**Step 3: Verify it compiles**

Run: `moon check`
Expected: 0 errors (warnings OK — `hybrid_memo_count` is unused so far)

**Step 4: Commit**

```bash
git add cells/runtime.mbt cells/push_propagate.mbt
git commit -m "feat: add hybrid_memo_count and mark_hybrid_dirty for lightweight dirty walk"
```

---

### Task 2: Wire up all call sites

Change `HybridMemo::new` to increment `hybrid_memo_count` instead of `node_count`. Update `Signal::set_unconditional`, `commit_batch`, and `fixpoint` to call `mark_hybrid_dirty` separately from `push_propagate_from`. Remove hybrid dirty-marking from `enqueue_push_subscribers` inside `push_propagate_from`.

**Files:**
- Modify: `cells/hybrid_memo.mbt:53` (change node_count → hybrid_memo_count)
- Modify: `cells/signal.mbt:196-200` (split gate into two)
- Modify: `cells/batch.mbt:178-181` (split gate into two)
- Modify: `cells/datalog_fixpoint.mbt:78-80` (split gate into two)
- Modify: `cells/push_propagate.mbt:161-167` (remove HybridMemo dirty-marking from enqueue_push_subscribers)

**Step 1: Change `HybridMemo::new`**

In `cells/hybrid_memo.mbt`, change line 53 from:
```moonbit
  rt.push.node_count = rt.push.node_count + 1
```
to:
```moonbit
  rt.push.hybrid_memo_count = rt.push.hybrid_memo_count + 1
```

**Step 2: Update `Signal::set_unconditional`**

In `cells/signal.mbt`, replace lines 198-200:
```moonbit
    if self.rt.push.node_count > 0 {
      self.rt.push_propagate_from([self.cell_id])
    }
```
with:
```moonbit
    if self.rt.push.hybrid_memo_count > 0 {
      self.rt.mark_hybrid_dirty([self.cell_id])
    }
    if self.rt.push.node_count > 0 {
      self.rt.push_propagate_from([self.cell_id])
    }
```

**Step 3: Update `commit_batch`**

In `cells/batch.mbt`, replace lines 178-181:
```moonbit
      if self.push.node_count > 0 {
        let changed_ids : Array[CellId] = changed.map(c => c.cell_id())
        self.push_propagate_from(changed_ids)
      }
```
with:
```moonbit
      let changed_ids : Array[CellId] = changed.map(c => c.cell_id())
      if self.push.hybrid_memo_count > 0 {
        self.mark_hybrid_dirty(changed_ids)
      }
      if self.push.node_count > 0 {
        self.push_propagate_from(changed_ids)
      }
```

**Step 4: Update `fixpoint`**

In `cells/datalog_fixpoint.mbt`, replace lines 78-80:
```moonbit
    if self.push.node_count > 0 {
      self.push_propagate_from(changed_ids)
    }
```
with:
```moonbit
    if self.push.hybrid_memo_count > 0 {
      self.mark_hybrid_dirty(changed_ids)
    }
    if self.push.node_count > 0 {
      self.push_propagate_from(changed_ids)
    }
```

**Step 5: Remove HybridMemo dirty-marking from `enqueue_push_subscribers`**

In `cells/push_propagate.mbt`, inside `enqueue_push_subscribers` (the inner `fn`), replace the `HybridMemo(i)` arm (lines 161-167):
```moonbit
          HybridMemo(i) => {
            if not(self.pull.memos[i].dirty) {
              self.pull.memos[i].dirty = true
              self.push.hybrid_dirty.push(sub_id)
            }
            bfs_worklist.push(sub_id) // bridge through hybrid memos
          }
```
with (keep bridging but remove dirty-marking):
```moonbit
          HybridMemo(_) => bfs_worklist.push(sub_id) // bridge through hybrid memos
```

Also remove the `hybrid_dirty.clear()` at the end of `push_propagate_from` (line 249) since `push_propagate_from` no longer populates it.

**Step 6: Run all tests**

Run: `moon test`
Expected: Total tests: 305, passed: 305, failed: 0.

**Step 7: Commit**

```bash
git add cells/hybrid_memo.mbt cells/signal.mbt cells/batch.mbt cells/datalog_fixpoint.mbt cells/push_propagate.mbt
git commit -m "refactor: separate hybrid dirty-marking from push propagation"
```

---

### Task 3: Update whitebox tests and run benchmarks

**Files:**
- Modify: `cells/push_reactive_wbtest.mbt` (update node_count test if needed)
- Modify: `cells/hybrid_wbtest.mbt` (add hybrid_memo_count test)

**Step 1: Add `hybrid_memo_count` whitebox test**

In `cells/hybrid_wbtest.mbt`, add:

```moonbit
///|
test "runtime: hybrid_memo_count tracks live hybrid memos" {
  let rt = Runtime::new()
  inspect(rt.push.hybrid_memo_count, content="0")
  inspect(rt.push.node_count, content="0")
  let s = Signal::new(rt, 0)
  let _h = HybridMemo::new(rt, fn() { s.get() * 2 })
  inspect(rt.push.hybrid_memo_count, content="1")
  inspect(rt.push.node_count, content="0") // hybrid memos don't count as push nodes
}
```

**Step 2: Run all tests**

Run: `moon test`
Expected: Total tests: 306, passed: 306, failed: 0.

**Step 3: Run benchmarks and compare**

Run: `moon bench --release`

Compare:
- `memo: get stale` vs `hybrid: get stale` — gap should be narrower
- `hybrid: get warm` — should be unchanged (~0.02 µs)

**Step 4: Commit**

```bash
git add cells/hybrid_wbtest.mbt
git commit -m "test: add hybrid_memo_count whitebox test"
```

---

### Task 4: Cleanup — clear hybrid_dirty in mark_hybrid_dirty

The `hybrid_dirty` array needs to be cleared after each propagation wave. Currently `push_propagate_from` clears it (line 249), but we removed that. The clearing should happen in the callers after both `mark_hybrid_dirty` and `push_propagate_from` have completed, or at the start of `mark_hybrid_dirty`.

**Files:**
- Modify: `cells/push_propagate.mbt` (clear hybrid_dirty at start of mark_hybrid_dirty)

**Step 1: Add clearing logic**

The `hybrid_dirty` array accumulates dirty cell IDs so that `pull_verify` can clear them. Looking at the current code, `hybrid_dirty` is only used inside `push_propagate_from` to track which hybrid memos were dirtied during the current wave — but it's never actually read by any other code (verify clears dirty via `memo.dirty = false` directly). Check if `hybrid_dirty` is read anywhere:

Run: `rg "hybrid_dirty" cells/` — if it's only written and cleared but never read for its contents, it can be removed entirely. If it is read, clear it at the end of `mark_hybrid_dirty`.

**Step 2: Run all tests**

Run: `moon test`
Expected: All tests pass.

**Step 3: Run `moon info && moon fmt`**

Verify no `.mbti` changes.

**Step 4: Commit**

```bash
git add cells/push_propagate.mbt
git commit -m "refactor: clean up hybrid_dirty lifecycle after separation"
```
