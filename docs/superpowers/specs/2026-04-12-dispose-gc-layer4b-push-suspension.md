# Layer 4b: Push Suspension + Scope::observe + MemoMap::sweep

**Status:** Approved
**Depends on:** Layer 4a (Observer + gc()) — merged in PR #31
**Blocked by:** Nothing
**Blocks:** Layer 5 (API boundary)

## Overview

Layer 4b fills in the real implementations of `CellLifecycle::on_observe` and `on_unobserve` for push-mode cells, adds `Scope::add_observer` for scoped observer lifecycle management, and provides `MemoMap::sweep` for post-gc cleanup.

Three features, each independent:

1. **Push suspension for PushReactive** — unsubscribe from upstream on last observer removal, recompute on first observer addition
2. **Scope::add_observer** — register an Observer with a Scope's dispose hooks
3. **MemoMap::sweep** — remove entries pointing to disposed memos after gc()

## Feature 1: Push Suspension for PushReactive

### Design Decision: Unsubscribe from Upstream (Option A)

When a PushReactive loses all observers AND has no downstream push demand (`push_reachable_count == 0`), it unsubscribes from all upstream sources. This makes the cell invisible to push propagation — no wasted BFS traversal, no dirty marking, no recomputation.

On reactivation (first observer added), the cell does a full recompute with fresh tracking to establish current sources and a correct cached value.

**Why not Option B (only manipulate push_reachable_count)?** The cell stays in subscriber sets, so the BFS still visits it on every signal change. With many suspended cells, this becomes O(N) wasted iteration per propagation wave.

**Why not a `suspended` flag?** The recompute on first observe is idempotent for fresh cells (add_subscriber early-returns if already subscribed). One redundant compute per cell lifetime is negligible compared to the complexity of maintaining a flag.

### Caller-Side Gating: 0→1 Transition

`on_observe` must only fire on the 0→1 observer count transition (symmetric with `on_unobserve`'s 1→0). Currently `on_observe` fires on every `observe()` call — harmless when it's a no-op, but Layer 4b makes it trigger a recompute.

**Change:** `Runtime::add_gc_root` returns the previous count. All three `observe()` methods (Memo, HybridMemo, Reactive) use it to gate `on_observe`:

```moonbit
fn Runtime::add_gc_root(self, id) -> Int {  // returns previous count
  match self.core.gc_root_counts.get(id) {
    Some(n) => { self.core.gc_root_counts.set(id, n + 1); n }
    None => { self.core.gc_root_counts.set(id, 1); 0 }
  }
}

// In each observe() method:
let prev = rt.add_gc_root(cell_id)
if prev == 0 {
  rt.core.cell_lifecycle[cell_id.id].on_observe(rt, cell_id)
}
```

### PushReactiveData::on_unobserve

```moonbit
impl CellLifecycle for PushReactiveData with on_unobserve(self, rt, cell_id) {
  // Only suspend if no downstream push cells depend on us
  guard self.meta.push_reachable_count == 0 else { return }
  for source in self.sources {
    rt.remove_subscriber(source, cell_id)
  }
}
```

`remove_subscriber` handles both subscriber set removal and `push_reachable_count` decrement upstream. The `sources` array is preserved (not cleared) — `dispose_cell` is idempotent because `remove_and_check` returns false for already-removed subscribers, preventing double-decrement of push_reachable_count.

`push.node_count` is NOT adjusted during suspension. It's a coarse O(1) gate ("any push nodes at all?"), not a correctness mechanism. The subscriber unlink is sufficient.

### PushReactiveData::on_observe

```moonbit
impl CellLifecycle for PushReactiveData with on_observe(self, rt, cell_id) {
  guard !rt.core.in_push_propagation else {
    abort("on_observe: cannot activate during push propagation")
  }
  // Full recompute with fresh tracking.
  // Pass [] as old_sources: subscriber links were removed during suspension.
  // For fresh cells (never suspended), add_subscriber is idempotent.
  rt.begin_tracking(cell_id)
  let _ = (self.compute)()
  let new_sources = rt.end_tracking()
  rt.finish_tracking(cell_id, [], new_sources)
  self.sources = new_sources
  self.level = rt.recompute_level(cell_id, new_sources)
  self.dirty = false
}
```

**Why full recompute?** During suspension, sources may have been disposed or changed. The cached value is stale (missed push updates). `Reactive::get()` returns the cached value without verification — it trusts push propagation to keep it current. Recomputing restores this invariant.

**Why `[]` as old_sources?** Subscriber links were removed during `on_unobserve`. `finish_tracking` diffs old vs new — passing `[]` causes it to call `add_subscriber` for ALL current sources.

**Fresh cell behavior:** For a cell that was never suspended, `add_subscriber` early-returns (subscriber already present). The recompute gets the same value. One wasted compute per cell lifetime — acceptable.

**Batch interaction:** If `on_observe` fires during a batch, the recompute reads pre-batch signal values. When the batch commits, push propagation recomputes the Reactive again with post-batch values. Double compute, but correct final state.

**Nested tracking:** `begin_tracking`/`end_tracking` use a stack. If `observe()` is called from inside a computation (unusual but possible), the Reactive's tracking frame nests correctly above the outer frame.

### HybridMemo and PullMemo: No-ops

`on_observe` and `on_unobserve` for `MemoData` remain the existing defaults (no-ops). Rationale:

1. **Pull verification handles correctness.** `HybridMemo::get()` calls `pull_verify`, which walks the `dependencies` array (not subscriber sets). Subscriber state is irrelevant to pull correctness.

2. **push_reachable_count handles downstream demand.** The BFS in `enqueue_push_subscribers` already skips HybridMemo/PullMemo branches where `push_reachable_count == 0`. No additional gating needed.

3. **Unsubscribing breaks downstream push paths.** If `Signal S → HybridMemo H → PushReactive R` and H unsubscribes from S on `on_unobserve`, the BFS from S can no longer reach R through H — even though `push_reachable_count(S) > 0` (from R via H). This is a correctness bug.

4. **gc() handles cleanup.** If `push_reachable_count == 0` AND no observers, the HybridMemo is unreachable from any root. `gc()` collects it, and `dispose_cell` handles subscriber cleanup.

## Feature 2: Scope::add_observer

```moonbit
pub fn[T] Scope::add_observer(self : Scope, obs : Observer[T]) -> Observer[T] {
  guard !self.disposed else {
    abort("Scope::add_observer called on a disposed scope")
  }
  self.dispose_hooks.push(fn() { obs.dispose() })
  obs
}
```

**Why a single generic method?** `add_observer` takes `Observer[T]` which works for all cell types. The user calls `.observe()` themselves. No per-cell-type overloads, no trait needed.

**Usage:**
```moonbit
let scope = Scope::new(rt)
let local = scope.memo(fn() { compute_layout(ast.get()) })
let obs = scope.add_observer(ast.observe())

scope.dispose()
// Step 1: children (bottom-up)
// Step 2: dispose_hooks → obs.dispose() → on_unobserve if last observer
// Step 3: owned cells (local memo)
```

**Safety:**
- `Observer::dispose()` is idempotent — safe if user disposes manually before scope disposal
- Disposal order (hooks before owned cells) prevents accessing already-disposed targets within the same scope
- If target was disposed externally, `Observer::dispose()` checks `is_cell_disposed` and skips `on_unobserve`

## Feature 3: MemoMap::sweep

```moonbit
pub fn[K : Hash + Eq, V] MemoMap::sweep(self : MemoMap[K, V]) -> Int {
  let to_remove : Array[K] = []
  for key, memo in self.entries {
    if memo.is_disposed() {
      to_remove.push(key)
    }
  }
  for key in to_remove {
    self.entries.remove(key)
  }
  to_remove.length()
}
```

**Two-pass** because HashMap iteration + mutation in the same pass is unsafe. Returns swept count for diagnostics/testing.

**When to call:** After `gc()`. gc disposes unreachable interior cells, setting their `cell_index` to `Disposed`. `sweep()` cleans up stale HashMap entries pointing to those disposed memos.

## Test Plan

1. **Suspend/activate cycle:** Create Reactive → observe → signal changes → verify value → unobserve → signal changes → re-observe → verify value caught up
2. **Suspension guard (push_reachable_count > 0):** `S → R1 → R2`, R2 observed, R1 not — verify R1 does NOT suspend, push propagation still reaches R2
3. **Multiple observers:** Two observers on same Reactive → dispose one → verify still active → dispose second → verify suspended
4. **GC of suspended cell:** Unobserve → gc() → verify cell collected
5. **Dispose during suspension:** Unobserve → dispose → verify no double-decrement (idempotent remove_subscriber)
6. **Source disposal during suspension:** Unobserve → dispose a source → re-observe → verify sources updated via fresh recompute
7. **Scope::add_observer lifecycle:** scope.add_observer(memo.observe()) → scope.dispose() → verify observer disposed, on_unobserve fired
8. **MemoMap::sweep after gc:** Populate entries → gc collects some → sweep() → verify entries removed, correct count returned

## Files Modified

| File | Change |
|------|--------|
| `cells/runtime.mbt` | `add_gc_root` returns previous count |
| `cells/observer.mbt` | Gate `on_observe` to 0→1 transition in all three observe methods |
| `cells/push_reactive.mbt` | `on_observe` and `on_unobserve` impls |
| `cells/scope.mbt` | Add `Scope::add_observer` method |
| `cells/memo_map.mbt` | Add `MemoMap::sweep` method |
| `cells/*_test.mbt` / `cells/*_wbtest.mbt` | Suspension cycle tests, scope observer tests |
| `tests/*_test.mbt` | Integration tests for all three features |
| `incr.mbt` | Re-export `Scope::add_observer`, `MemoMap::sweep` if needed |

## Non-goals (Future Work)

- **Recursive suspension:** When `push_reachable_count` drops to 0 on an unobserved cell, automatically trigger suspension. Deferred — gc() handles cleanup.
- **Lazy MemoMap recreation:** Detect disposed entry in `get()` and recreate fresh. Deferred — sweep() is sufficient.
- **HybridMemo push activation:** Direct push notifications to keep `verified_at` current for observed HybridMemos. Would require architecture changes to push propagation.
