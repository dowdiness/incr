# Push Reachable Count — Design Spec

**Date:** 2026-03-25
**Status:** Approved
**Scope:** Approach A (signal-level outer gate), Approach B (full per-cell BFS pruning) to follow

---

## Problem

When any push cell (Reactive or Effect) exists in a graph, `signal.set()` calls `push_propagate_from`, which runs a BFS through all subscriber links to find downstream push nodes. This BFS traverses hybrid memo and pull memo subscribers even when no push node is reachable downstream of the changed signal.

**Benchmark (release mode):**

| Scenario | Cost |
|---|---|
| 100 hybrid subs, no push nodes (BFS skipped by `node_count` gate) | 0.03 µs |
| 100 hybrid subs, distant reactive (`node_count > 0`, BFS runs) | 2.47 µs |
| 1000 hybrid subs, distant reactive | 52.94 µs |

The 82× overhead at 100 subscribers scales linearly to 1,700× at 1,000.

**Root cause:** The existing `push.node_count > 0` gate only fires when there are zero push cells anywhere. A single distant reactive triggers the full BFS for every signal change in the graph, regardless of whether that signal feeds into any push path.

**Inspiration:** alien-signals' `ReactiveFlags.Mutable` — each node carries a flag meaning "subscribers exist downstream." During `propagate()`, nodes without `Mutable` are not descended into. We adapt this idea to our two-tier (pull/push) graph.

---

## Approach A — `push_reachable_count` on signals (outer gate)

### What it does

Adds `push_reachable_count : Int` to `PullSignalData`. A signal's count equals the number of live push cells (Reactive/Effect) that transitively depend on it through the subscriber graph. Before running the BFS for a signal, check this count; if zero, skip immediately.

### Data model change

In `cells/pull_signal.mbt`, add one field to `PullSignalData`:

```moonbit
priv struct PullSignalData {
  meta : CellMeta
  mut on_change : (() -> Unit)?
  mut commit_pending : (() -> Unit)?
  mut push_reachable_count : Int   // NEW
}
```

### Maintenance — 3 chokepoints

**1. Reactive/Effect first compute**
After `finish_tracking` returns the initial `new_sources` for a reactive or effect, for each source: if it is a `PullSignal`, increment its `push_reachable_count`. If it is a `PullMemo` or `HybridMemo`, walk its `dependencies` recursively and increment every `PullSignal` found.

New helper: `Runtime::increment_signal_push_reachable(sources: Array[CellId])`.

**2. Reactive/Effect dispose**
In `Runtime::dispose_reactive` and `Runtime::dispose_effect`, after removing from subscriber sets, call `Runtime::decrement_signal_push_reachable(sources)` over the same source arrays.

**3. Source set changes on recompute**
In `push_propagate.mbt`, after `finish_tracking` diffs old/new sources during a reactive/effect recompute:
- For each removed source: `decrement_signal_push_reachable([removed])`
- For each added source: `increment_signal_push_reachable([added])`

### The gate

In `push_propagate.mbt`, inside `enqueue_push_subscribers(source_id)`:

```moonbit
// O(1) gate: skip BFS entirely if no push cell is downstream of this signal
match self.core.cell_index[source_id.id] {
  PullSignal(idx) =>
    if self.pull.signals[idx].push_reachable_count == 0 {
      return
    }
  _ => ()
}
// ... existing BFS
```

### Staleness

Pull/hybrid memo dependency sets can change when memos recompute. In Approach A, signal-level counts are only updated when reactive/effect sources change — not when intermediate memo deps change. This can cause false positives (BFS runs for a signal that no longer has a push path through a given memo chain) but never false negatives (missed push notifications). False positives are wasteful but not incorrect.

Approach B eliminates this by maintaining the count on all `CellMeta` and updating it during memo dep changes.

---

## Approach B — `push_reachable_count` on all `CellMeta` (full BFS pruning)

*To be implemented after Approach A is benchmarked and validated.*

### What it adds over A

Moves `push_reachable_count` from `PullSignalData` to `CellMeta`, making it available on every cell type. The BFS in `enqueue_push_subscribers` can then skip any `HybridMemo` or `PullMemo` subscriber whose count is zero — pruning dead branches within the BFS, not just at the outer gate.

A fourth maintenance chokepoint is added: when a pull/hybrid memo's dependency set changes in `memo_force_recompute`, if the memo's own `push_reachable_count > 0`, propagate the delta (added/removed deps × memo's count) upward through changed dependencies.

### Expected improvement over A

For graphs where push nodes are downstream of some but not all hybrid memo subscribers of a signal, Approach B skips the dead-end branches. For the benchmark scenario (zero push downstream), A and B are equivalent — both gate at O(1).

---

## CellOps extension (Approach B only)

Add `push_reachable_count(Self) -> Int` to the `CellOps` trait with a default impl reading `self.meta.push_reachable_count`. This enables uniform dispatch in `enqueue_push_subscribers` without SoA index lookups.

---

## Testing

### Whitebox tests (`cells/push_propagate_wbtest.mbt` or `cells/push_efficiency_wbtest.mbt`)

- Signal with no reactive downstream: `push_reachable_count == 0`
- Signal with one direct reactive: count == 1
- Signal with one reactive through a hybrid memo: count == 1
- Reactive dispose: count returns to 0
- Reactive source change: count updated on old and new signal
- Double-dispose: count does not go negative

### Benchmarks

Re-run `cells/push_efficiency_bench_test.mbt` after Approach A. Target: mixed-graph benchmark matches baseline (≤ 0.05 µs for 100 hybrid subs).

### Regression

All 323 existing tests must pass unchanged.

---

## Files changed (Approach A)

| File | Change |
|---|---|
| `cells/pull_signal.mbt` | Add `push_reachable_count : Int` field |
| `cells/runtime.mbt` | Add `increment_signal_push_reachable`, `decrement_signal_push_reachable` helpers |
| `cells/push_propagate.mbt` | Add O(1) gate in `enqueue_push_subscribers`; update source-change diff to call helpers |
| `cells/push_reactive.mbt` / `cells/push_effect.mbt` | Call increment on creation, decrement via dispose helpers |
| `cells/push_efficiency_bench_test.mbt` | Verify benchmark improvement |
| `cells/push_reachable_wbtest.mbt` (new) | Whitebox tests for count maintenance |
