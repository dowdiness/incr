# Layer 4b: Push Suspension + scoped watches + DerivedMap::sweep_cache

**Status:** Approved
**Depends on:** Layer 4a (Watch + gc()) — merged in PR #31
**Blocked by:** Nothing
**Blocks:** Layer 5 (API boundary)

## Overview

Layer 4b fills in the real implementations of `CellLifecycle::on_observe` and `on_unobserve` for push-mode cells, adds `Scope::add_watch` for scoped watch lifecycle management, and provides `DerivedMap::sweep_cache` for post-gc cleanup.

Three features, each independent:

1. **Push suspension for PushReactive** — unsubscribe from upstream on last watch removal, recompute on first watch addition
2. **Scope::add_watch** — register a Watch with a Scope's dispose hooks
3. **DerivedMap::sweep_cache** — remove entries pointing to disposed memos after gc()

## Feature 1: Push Suspension for PushReactive

### Design Decision: Unsubscribe from Upstream (Option A)

When a PushReactive loses all watches AND has no subscribers at all (no downstream push cells, no downstream pull memos), it unsubscribes from all upstream sources. This makes the cell invisible to push propagation — no wasted BFS traversal, no dirty marking, no recomputation.

On reactivation (first watch added), the cell does a full recompute with fresh tracking to establish current sources and a correct cached value.

**Why not Option B (only manipulate push_reachable_count)?** The cell stays in subscriber sets, so the BFS still visits it on every signal change. With many suspended cells, this becomes O(N) wasted iteration per propagation wave.

**Why not a `suspended` flag?** The recompute on first watch is idempotent for fresh cells (add_subscriber early-returns if already subscribed). One redundant compute per cell lifetime is negligible compared to the complexity of maintaining a flag.

### Caller-Side Gating: 0→1 Transition

`on_observe` must only fire on the 0→1 watch count transition (symmetric with `on_unobserve`'s 1→0). Currently `on_observe` fires on every `watch()` call — harmless when it's a no-op, but Layer 4b makes it trigger a recompute.

**Change:** `Runtime::add_gc_root` returns the previous count. All three `watch()` methods (Derived, ReachableDerived, EagerDerived) use it to gate `on_observe`:

```moonbit
fn Runtime::add_gc_root(self, id) -> Int {  // returns previous count
  match self.core.gc_root_counts.get(id) {
    Some(n) => { self.core.gc_root_counts.set(id, n + 1); n }
    None => { self.core.gc_root_counts.set(id, 1); 0 }
  }
}

// In each watch() method:
let prev = rt.add_gc_root(cell_id)
if prev == 0 {
  rt.core.cell_lifecycle[cell_id.id].on_observe(rt, cell_id)
}
```

### PushReactiveData::on_unobserve

```moonbit
impl CellLifecycle for PushReactiveData with on_unobserve(self, rt, cell_id) {
  // Only suspend if nobody reads us — neither push cells nor pull memos.
  // push_reachable_count == 0 is insufficient: a Derived that pull-verifies
  // this EagerDerived checks changed_at, which only advances during push
  // propagation. Suspending (unsubscribing) would freeze changed_at,
  // causing the downstream Derived to return stale data.
  guard self.meta.subscribers.is_empty() else { return }
  for source in self.sources {
    rt.remove_subscriber(source, cell_id)
  }
}
```

The guard checks `subscribers.is_empty()` — if ANY cell (push or pull) reads this EagerDerived, it must stay subscribed upstream so its `changed_at` advances correctly on source changes.

`remove_subscriber` handles both subscriber set removal and `push_reachable_count` decrement upstream. The `sources` array is preserved (not cleared) — `dispose_cell` is idempotent because `remove_and_check` returns false for already-removed subscribers, preventing double-decrement of push_reachable_count.

`push.node_count` is NOT adjusted during suspension. It's a coarse O(1) gate ("any push nodes at all?"), not a correctness mechanism. The subscriber unlink is sufficient.

### PushReactiveData::on_observe

```moonbit
impl CellLifecycle for PushReactiveData with on_observe(self, rt, cell_id) {
  guard !rt.core.in_push_propagation else {
    abort("on_observe: cannot activate during push propagation")
  }
  guard !rt.core.in_fixpoint else {
    abort("on_observe: cannot activate during fixpoint evaluation")
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

**Why full recompute?** During suspension, sources may have been disposed or changed. The cached value is stale (missed push updates). `EagerDerived::get()` returns the cached value without verification — it trusts push propagation to keep it current. Recomputing restores this invariant.

**Why `[]` as old_sources?** Subscriber links were removed during `on_unobserve`. `finish_tracking` diffs old vs new — passing `[]` causes it to call `add_subscriber` for ALL current sources.

**Fresh cell behavior:** For a cell that was never suspended, `add_subscriber` early-returns (subscriber already present). The recompute gets the same value. One wasted compute per cell lifetime — acceptable.

**Batch interaction:** If `on_observe` fires during a batch, the recompute reads pre-batch signal values. When the batch commits, push propagation recomputes the EagerDerived again with post-batch values. Double compute, but correct final state.

**Nested tracking:** `begin_tracking`/`end_tracking` use a stack. If `watch()` is called from inside a computation (unusual but possible), the EagerDerived's tracking frame nests correctly above the outer frame.

### ReachableDerived and PullMemo: No-ops

`on_observe` and `on_unobserve` for `MemoData` remain the existing defaults (no-ops). Rationale:

1. **Pull verification handles correctness.** `ReachableDerived::get()` calls `pull_verify`, which walks the `dependencies` array (not subscriber sets). Subscriber state is irrelevant to pull correctness.

2. **push_reachable_count handles downstream demand.** The BFS in `enqueue_push_subscribers` already skips ReachableDerived/PullMemo branches where `push_reachable_count == 0`. No additional gating needed.

3. **Unsubscribing breaks downstream push paths.** If `Input S → ReachableDerived H → PushReactive R` and H unsubscribes from S on `on_unobserve`, the BFS from S can no longer reach R through H — even though `push_reachable_count(S) > 0` (from R via H). This is a correctness bug.

4. **gc() handles cleanup.** If `push_reachable_count == 0` AND no watches, the ReachableDerived is unreachable from any root. `gc()` collects it, and `dispose_cell` handles subscriber cleanup.

## Feature 2: Scope::add_watch

```moonbit
pub fn[T] Scope::add_watch(self : Scope, watch : Watch[T]) -> Watch[T] {
  guard !self.disposed else {
    abort("Scope::add_watch called on a disposed scope")
  }
  self.dispose_hooks.push(fn() { watch.dispose() })
  watch
}
```

**Why a single generic method?** `add_watch` takes `Watch[T]` which works for all cell types. The user calls `.watch()` themselves. No per-cell-type overloads, no trait needed.

**Usage:**
```moonbit
let scope = Scope::new(rt)
let local = scope.derived(fn() { compute_layout(ast.get()) })
let obs = scope.add_watch(ast.watch())

scope.dispose()
// Step 1: children (bottom-up)
// Step 2: dispose_hooks → obs.dispose() → on_unobserve if last watch
// Step 3: owned cells (local memo)
```

**Safety:**
- `Watch::dispose()` is idempotent — safe if user disposes manually before scope disposal
- Disposal order (hooks before owned cells) prevents accessing already-disposed targets within the same scope
- If target was disposed externally, `Watch::dispose()` checks `is_cell_disposed` and skips `on_unobserve`

## Feature 3: DerivedMap::sweep_cache

```moonbit
pub fn[K : Hash + Eq, V] DerivedMap::sweep_cache(self : DerivedMap[K, V]) -> Int {
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

**When to call:** After `gc()`. gc disposes unreachable interior cells, setting their `cell_index` to `Disposed`. `sweep_cache()` cleans up stale HashMap entries pointing to those disposed memos.

## Test Plan

1. **Suspend/activate cycle:** Create EagerDerived → watch → signal changes → verify value → dispose → signal changes → watch again → verify value caught up
2. **Suspension guard (subscribers non-empty):** `S → R1 → R2`, R2 watched, R1 not — verify R1 does NOT suspend, push propagation still reaches R2
3. **Pull subscriber prevents suspension:** `S → EagerDerived R → Derived M`, M reads R. R's watch disposed — verify R does NOT suspend (M is in R's subscriber set), M.get() still returns correct value after S changes
4. **Pull subscriber with ReachableDerived:** Same as above but `S → EagerDerived R → ReachableDerived H` — verify R stays active, H.get() returns correct value
5. **Multiple watches:** Two watches on same EagerDerived → dispose one → verify still active → dispose second → verify suspended
6. **GC of suspended cell:** Dispose watch → gc() → verify cell collected
7. **Dispose during suspension:** Dispose watch → dispose → verify no double-decrement (idempotent remove_subscriber)
8. **Source disposal during suspension:** Dispose watch → dispose a source → watch again → verify sources updated via fresh recompute
9. **Repeated 0→1 transitions on fresh cell:** Watch → dispose → watch again → dispose on an EagerDerived that has no subscribers — verify each cycle works, no stale state
10. **on_observe during fixpoint aborts:** Attempt to watch an EagerDerived during fixpoint() — verify abort
11. **Scope::add_watch lifecycle:** scope.add_watch(derived.watch()) → scope.dispose() → verify watch disposed, on_unobserve fired
12. **DerivedMap::sweep_cache after gc:** Populate entries → gc collects some → sweep_cache() → verify entries removed, correct count returned

## Files Modified

| File | Change |
|------|--------|
| `cells/runtime.mbt` | `add_gc_root` returns previous count |
| `cells/watch.mbt` | Gate `on_observe` to 0→1 transition in all three watch methods |
| `cells/eager_derived.mbt` | `on_observe` and `on_unobserve` impls |
| `cells/scope.mbt` | Add `Scope::add_watch` method |
| `cells/derived_map.mbt` | Add `DerivedMap::sweep_cache` method |
| `cells/*_test.mbt` / `cells/*_wbtest.mbt` | Suspension cycle tests, scope watch tests |
| `tests/*_test.mbt` | Integration tests for all three features |
| `incr.mbt` | Re-export `Scope::add_watch`, `DerivedMap::sweep_cache` if needed |

## Non-goals (Future Work)

- **Recursive suspension:** When `push_reachable_count` drops to 0 on an disposed cell, automatically trigger suspension. Deferred — gc() handles cleanup.
- **Lazy DerivedMap recreation:** Detect disposed entry in `get()` and recreate fresh. Deferred — sweep_cache() is sufficient.
- **ReachableDerived push activation:** Direct push notifications to keep `verified_at` current for watched HybridMemos. Would require architecture changes to push propagation.
