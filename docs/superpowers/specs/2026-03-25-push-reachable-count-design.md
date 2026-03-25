# Push Reachable Count — Design Spec

**Date:** 2026-03-25
**Status:** Approved
**Scope:** Approach A (signal-level outer gate), Approach B (full per-cell BFS pruning) to follow

---

## Problem

When any push cell (Reactive or Effect) exists in a graph, `signal.set()` calls `push_propagate_from`, which runs a BFS through all subscriber links to find downstream push nodes. This BFS traverses HybridMemo and PullMemo subscribers even when no push node is reachable downstream of the changed signal.

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
  mut commit_pending : (() -> Bool)?
  mut push_reachable_count : Int   // NEW
}
```

(`CellMeta` is defined in `cells/cell_ops.mbt`.)

### Counting semantics — one increment per (reactive, signal) pair

`push_reachable_count` counts live push cells, not traversal paths. In a diamond topology (`sig → memoA → reactive`, `sig → memoB → reactive`), `sig.push_reachable_count` must be 1 (one reactive), not 2 (two paths).

The increment/decrement helpers must therefore **deduplicate signals** across a single reactive's source tree before adjusting counts. The walk collects a `HashSet[CellId]` of all transitively reachable `PullSignal` IDs for a given reactive, then increments each by exactly 1.

Invariant: `sig.push_reachable_count` equals the number of live Reactive/Effect cells for which `sig` is a transitive signal dependency.

### Two helpers

**`Runtime::collect_reachable_signals(sources: Array[CellId]) -> @hashset.HashSet[CellId]`**

Walk `sources`. For each source:
- `PullSignal` → add its `CellId` to the set
- `PullMemo(idx)` or `HybridMemo(idx)` → recurse into `pull.memos[idx].dependencies`
- All other variants → ignore

Returns a deduplicated set of all `PullSignal` IDs transitively reachable from `sources`.

**`Runtime::adjust_signal_push_reachable(sources: Array[CellId], delta: Int)`**

Calls `collect_reachable_signals(sources)` and adds `delta` (+1 or -1) to `push_reachable_count` on each signal in the result. Asserts that no count goes negative.

### Maintenance — 3 chokepoints

**1. Reactive/Effect creation (first compute)**

`Reactive::new` and `Effect::new` each call `begin_tracking` / `end_tracking` / `finish_tracking` synchronously during construction. After `finish_tracking` establishes `new_sources`:

```moonbit
self.adjust_signal_push_reachable(new_sources, +1)
```

Sources are populated before `new` returns, so the reactive is always in a consistent state from the moment of construction. `dispose_reactive`/`dispose_effect` call `adjust_signal_push_reachable(sources, -1)` before `clear_slot()`, ensuring the count adjustment uses a valid source array. Under staleness (intermediate memo deps changed between creation and dispose), the dispose walk uses the current memo dep graph rather than the historical one, so it may not decrement the same signals that were incremented. This can leave some signal counts slightly above zero (a persistent false positive) or decrement a signal that was never incremented for this reactive (a transient false positive on an unrelated path). Both outcomes are acceptable: Approach A explicitly tolerates imprecise counts — false positives mean unnecessary BFS runs, not missed notifications. The slot reuse invariant (`free_reactives`/`free_effects`) is safe because `clear_slot()` and free-list insertion happen after the count adjustment.

**2. Reactive/Effect dispose**

In `Runtime::dispose_reactive` and `Runtime::dispose_effect`, after removing from subscriber sets and before `clear_slot()`:

```moonbit
self.adjust_signal_push_reachable(reactive.sources, -1)
// then: clear_slot(), push to free list, decrement node_count
```

**3. Source set changes on recompute**

In `push_propagate.mbt`, after `finish_tracking` diffs old/new sources during a reactive/effect recompute, call:

```moonbit
self.adjust_signal_push_reachable(removed_sources, -1)
self.adjust_signal_push_reachable(added_sources, +1)
```

Where `removed_sources` and `added_sources` are the source IDs that left/joined the set in this recompute cycle. Each helper internally deduplicates, so a signal reachable via both a removed and an added path is adjusted correctly.

Note: when a source is a `PullMemo` or `HybridMemo`, the helper walks its `dependencies` to reach signals — exactly as in chokepoint 1. This must not be omitted even when the source itself is a memo rather than a signal.

### The gate

In `push_propagate.mbt`, inside the `enqueue_push_subscribers` closure (which is called both for initial `changed_sources` and for reactive outputs after recompute):

```moonbit
fn enqueue_push_subscribers(source_id : CellId) -> Unit {
  // O(1) gate: skip BFS if no push cell is downstream of this signal
  match self.core.cell_index[source_id.id] {
    PullSignal(idx) =>
      if self.pull.signals[idx].push_reachable_count == 0 {
        return
      }
    _ => ()  // non-signal sources (e.g. relations) are not gated here
  }
  // ... existing BFS unchanged
}
```

The `_ => ()` arm is intentional: when `enqueue_push_subscribers` is called with a `PushReactive` cell ID (line 210 of `push_propagate.mbt`, after a reactive recomputes), the gate is a no-op and the BFS runs normally. Relation and FunctionalRelation sources also fall through — Approach A provides no gate for relation-sourced BFS (see Limitations).

The gate does not apply to the batch path: `commit_batch` calls `push_propagate_from` with signal IDs, which are `PullSignal` in `cell_index`, so the gate fires naturally with no additional work.

### Staleness (false positives only, never false negatives)

Pull/hybrid memo dependency sets can change when memos lazily recompute. Under Approach A, signal-level counts are only updated when reactive/effect sources change — not when intermediate memo deps change. Example: reactive depends on `memoA`, `memoA` depends on `sig1`, then `memoA` recomputes to depend on `sig2`. After this:

- `sig1.push_reachable_count` stays at 1 (should be 0) — false positive: BFS runs unnecessarily for `sig1`
- `sig2.push_reachable_count` stays at 0 (should be 1) — BFS is skipped for `sig2`

Skipping the BFS for `sig2` looks like a false negative but is not a correctness bug: the reactive's source set still contains `memoA`, and `memoA` is still in `sig2`'s subscriber set (maintained synchronously). The BFS starting from `sig2` would traverse `memoA`'s subscriber list and find the reactive regardless. The subscriber-link graph is always accurate; only the signal-level count can be stale.

Approach B eliminates this by maintaining the count on all `CellMeta` and updating it during memo dep changes.

### Limitations (Approach A)

- **Relation sources:** Approach A provides no gate for relation-sourced BFS (`Relation`/`FunctionalRelation` cells are not `PullSignal` and are not counted). A reactive that depends on a Relation does not contribute to any signal's `push_reachable_count`.
- **Reactive-bridge sources:** `collect_reachable_signals` does not recurse into `PushReactive` sources. If a reactive A depends on reactive B, the signals upstream of B are not counted for A's contribution. Signals reachable only through reactive-to-reactive paths are not gated.
- **Staleness:** When intermediate memo deps change, signal-level counts may drift (false positives). BFS runs unnecessarily for affected signals but never misses a push notification.

---

## Approach B — `push_reachable_count` on all `CellMeta` (full BFS pruning)

*To be implemented after Approach A is benchmarked and validated.*

### What it adds over A

Moves `push_reachable_count` from `PullSignalData` to `CellMeta` (in `cells/cell_ops.mbt`), making it available on every cell type via `HasCellMeta`. The BFS in `enqueue_push_subscribers` can then skip any `HybridMemo` or `PullMemo` subscriber whose count is zero — pruning dead branches within the BFS, not just at the outer gate.

A fourth maintenance chokepoint is added: when a pull/hybrid memo's dependency set changes in `memo_force_recompute`, if the memo's own `push_reachable_count > 0`, propagate the delta (× memo's count) upward through changed dependencies. This eliminates Approach A's staleness.

`CellOps` gains `push_reachable_count(Self) -> Int` with a default impl reading `self.meta.push_reachable_count`, enabling uniform dispatch in `enqueue_push_subscribers`.

### Expected improvement over A

For graphs where push nodes are downstream of some but not all hybrid memo subscribers of a signal, Approach B skips dead-end branches within the BFS. For the benchmark scenario (zero push downstream of any signal), A and B are equivalent — both gate at O(1).

---

## Testing

### Whitebox tests (`cells/push_reachable_wbtest.mbt`, new file)

- Signal with no reactive downstream: `push_reachable_count == 0`
- Signal with one direct reactive: count == 1
- Signal with one reactive through a hybrid memo (one bridge): count == 1
- Signal with one reactive through a two-deep memo chain (`sig → memoA → memoB → reactive`): count == 1
- **Diamond topology** (`sig → memoA → reactive`, `sig → memoB → reactive`): count == 1 (not 2); after dispose, count == 0
- Reactive dispose: count returns to 0
- Reactive source change (reads `sig1` then changes to `sig2`): `sig1.count == 0`, `sig2.count == 1`
- Double-dispose: count does not go negative (assert fires)
- Gate behavioral test: `signal.set()` on a signal with count == 0 does not enqueue any push entries (verify via a side-channel, e.g. a reactive that should NOT fire does not fire)
- Dispose after intermediate memo dep change: create reactive reading `memoA` which reads `sig1`; verify `sig1.count == 1`; trigger `memoA` to recompute reading `sig2` instead; dispose the reactive; verify no count goes negative and the system remains in a consistent (non-aborting) state

### Benchmarks

Re-run `cells/push_efficiency_bench_test.mbt` after Approach A. Target: mixed-graph benchmarks match baseline (≤ 0.05 µs for 100 and 1000 hybrid subs with distant reactive).

### Regression

All 323 existing tests must pass unchanged.

---

## Files changed (Approach A)

| File | Change |
|---|---|
| `cells/pull_signal.mbt` | Add `push_reachable_count : Int` field to `PullSignalData` |
| `cells/runtime.mbt` | Add `collect_reachable_signals`, `adjust_signal_push_reachable` helpers |
| `cells/push_propagate.mbt` | Add O(1) gate in `enqueue_push_subscribers`; call adjust helpers on source-set diff |
| `cells/push_reactive.mbt` | Call `adjust_signal_push_reachable(sources, +1)` after first `finish_tracking` |
| `cells/push_effect.mbt` | Same as push_reactive.mbt |
| `cells/runtime.mbt` | Call `adjust_signal_push_reachable(sources, -1)` in `dispose_reactive` and `dispose_effect` |
| `cells/push_reachable_wbtest.mbt` (new) | Whitebox tests for count maintenance |
| `cells/push_efficiency_bench_test.mbt` | Verify benchmark improvement |
