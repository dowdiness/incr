# Push Reachable Count — Design Spec

**Date:** 2026-03-25
**Status:** Approved
**Scope:** `push_reachable_count` on all `CellMeta` — outer gate + inner BFS pruning

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

## Approach — `push_reachable_count` on all `CellMeta`

### What it does

Adds `push_reachable_count : Int` to `CellMeta`. Every cell in the graph tracks the total subscriber-path weight to live push cells (Reactive/Effect) reachable downstream.

- The outer gate in `enqueue_push_subscribers` skips the BFS entirely if the source cell's count is zero.
- Within the BFS, subscriber links that lead through a memo with count zero are pruned, avoiding dead-end traversals.

### Why not a signal-only count (Approach A)?

A signal-only count fails when intermediate memo dependencies change. If a memo M dynamically switches from reading `sig1` to reading `sig2`, `sig2.push_reachable_count` remains zero and `sig2.set()` would skip the BFS — silently missing the downstream reactive. Placing the count on `CellMeta` and maintaining it in `add_subscriber`/`remove_subscriber` ensures updates propagate correctly whenever any dependency link changes, regardless of depth.

---

## Data model change

### `CellMeta` (`cells/cell_ops.mbt`)

Add one field:

```moonbit
priv struct CellMeta {
  cell_id : CellId
  mut label : String?
  mut changed_at : Revision
  mut durability : Durability
  subscribers : @hashset.HashSet[CellId]
  mut push_reachable_count : Int   // NEW
}
```

### `CellOps` trait (`cells/cell_ops.mbt`)

Add one method with a default implementation reading from `CellMeta`:

```moonbit
trait CellOps: HasCellMeta {
  // ... existing methods ...
  push_reachable_count(Self) -> Int = _
}

///|
impl CellOps with push_reachable_count(self) -> Int {
  HasCellMeta::meta(self).push_reachable_count
}
```

---

## Count semantics — subscriber-path weight

`push_reachable_count` on cell C counts the total subscriber-path weight to live push cells. This is equivalent to: for each subscriber link in the BFS from C, how many push-cell endpoints are reachable?

In a diamond topology (`sig → memoA → reactive`, `sig → memoB → reactive`):

- `memoA.push_reachable_count` = 1 (one path to reactive)
- `memoB.push_reachable_count` = 1 (one path to reactive)
- `sig.push_reachable_count` = 2 (two paths to reactive, through memoA and memoB)

After disposing reactive:
- `memoA.push_reachable_count` = 0
- `memoB.push_reachable_count` = 0
- `sig.push_reachable_count` = 0

The gate condition `push_reachable_count == 0` correctly closes when no push cell is reachable, and opens (count > 0) whenever any path exists — which is the only property the gate needs.

**Invariant (gate invariant, not exact path count):** `cell.push_reachable_count > 0` if and only if at least one live push cell is reachable downstream from `cell` through subscriber links.

The count is a subscriber-path weight, not a count of distinct push cells. In a diamond topology, `sig.count = 2` represents two paths to one reactive — that is fine. The invariant only requires the zero/non-zero distinction to be correct, not the exact magnitude. `Int` overflow in pathologically deep diamond graphs is theoretically possible but not a concern for realistic reactive graphs (would require on the order of 2^31 independent diamond fan-in paths converging on a single signal).

---

## Two helpers (`cells/runtime.mbt`)

### `Runtime::collect_reachable_cells(sources: Array[CellId]) -> @hashset.HashSet[CellId]`

Walk `sources` upstream through the dependency graph. For each unvisited source:
- `PullSignal` → add to set; stop (leaf, no further deps)
- `PullMemo(idx)` or `HybridMemo(idx)` → add to set; recurse into `pull.memos[idx].dependencies`
- `PushReactive`, `Relation`, `FunctionalRelation`, `Rule` → **add to set; stop (do not recurse)**
- `Disposed` → skip (do not add)
- Use a visited set to prevent revisiting cells in DAGs (no memo cycles exist, but diamond fan-in is common)

Returns a deduplicated set of cell IDs whose `push_reachable_count` must be adjusted. Crucially, **non-pull source cells (`PushReactive`, `Relation`, `FunctionalRelation`) are included in the set** so that `adjust_push_reachable([R1], +1)` increments `R1.push_reachable_count` directly. This is required for the outer gate to work when `enqueue_push_subscribers` is called with a reactive output or a relation as the source.

Non-pull cells are leaf nodes in the count-propagation walk — their own sources are managed independently through the push propagation level system and do not need upstream count propagation here.

**Uncomputed memos:** A memo that has never been computed has an empty `dependencies` array, so `collect_reachable_cells` returns `{memo}` (just the memo itself). The upstream signals are registered later, during the memo's first `memo_force_recompute`, which calls `add_subscriber(signal, memo)` for each discovered dep — and at that point the signal's count is updated via `adjust_push_reachable([signal], memo.push_reachable_count)`.

Two cases:
- **Reactive reads memo first (common case):** `add_subscriber(memo, reactive)` fires before the memo is computed (via `finish_tracking` during `Reactive::new`). `memo.push_reachable_count` becomes 1. When the reactive's first compute calls `memo.get()` → `memo_force_recompute`, `add_subscriber(signal, memo)` fires with contribution=1, correctly incrementing `signal.push_reachable_count`.
- **User code calls `Memo::get()` first:** `memo_force_recompute` fires with `memo.push_reachable_count = 0`. `add_subscriber(signal, memo)` fires with contribution=0 — a no-op for `signal.push_reachable_count`. Correct: no reactive is yet downstream, so `signal.push_reachable_count` should be 0. When a reactive later subscribes to the memo, `add_subscriber(memo, reactive)` calls `adjust_push_reachable([memo], 1)`. At that point `memo.dependencies` is already populated (from the prior `Memo::get()`), so `collect_reachable_cells([memo])` includes `signal`, and `signal.push_reachable_count` is incremented correctly.

### `Runtime::adjust_push_reachable(sources: Array[CellId], delta: Int)`

Calls `collect_reachable_cells(sources)` and adds `delta` to `push_reachable_count` on each cell in the result. Asserts that no count goes negative.

---

## Maintenance — centralized in `add_subscriber`/`remove_subscriber`

All maintenance scenarios (push cell creation, push cell dispose, push source-set changes on recompute, memo dep changes, and HybridMemo dispose) are handled by hooking into `add_subscriber` and `remove_subscriber`. No additional chokepoints are needed.

### `Runtime::push_contribution(sub_id) -> Int` (new private helper)

```moonbit
fn Runtime::push_contribution(self : Runtime, sub_id : CellId) -> Int {
  match self.core.cell_index[sub_id.id] {
    PushReactive(_) | PushEffect(_) => 1
    PullMemo(i) | HybridMemo(i) => self.pull.memos[i].meta.push_reachable_count
    _ => 0
  }
}
```

Returns 0 for `Relation`, `FunctionalRelation`, `Rule`, and `Disposed`. Datalog Rules are not push cells — they drive fixpoint iteration, not the push reactive graph. A `Reactive` that directly reads from a `Relation` subscribes to it via `add_subscriber(relation, reactive)` with contribution=1 (R is `PushReactive`), correctly setting `relation.push_reachable_count = 1` so the outer gate stays open for relation-sourced BFS calls during fixpoint evaluation.

### `Runtime::add_subscriber(dep_id, sub_id)` (extended)

After adding `sub_id` to `dep_id`'s subscriber set (existing behavior):

```moonbit
let contribution = self.push_contribution(sub_id)
if contribution > 0 {
  self.adjust_push_reachable([dep_id], contribution)
}
```

### `Runtime::remove_subscriber(dep_id, sub_id)` (extended)

Compute the contribution *before* removing from the set, then remove, then adjust:

```moonbit
let contribution = self.push_contribution(sub_id)
dep's subscriber set .remove(sub_id)  // existing removal
if contribution > 0 {
  self.adjust_push_reachable([dep_id], -contribution)
}
```

Computing contribution before removal is critical: `push_contribution` reads `sub_id`'s `CellRef` and `CellMeta`. The `CellRef` for a reactive/effect is changed to `Disposed` during `dispose_reactive`/`dispose_effect` after `remove_subscriber` completes. If contribution were computed after `sub_id` is marked `Disposed`, `push_contribution` would return 0 and the decrement would be skipped. The ordering constraint is: compute contribution **before the subscriber cell's CellRef is set to Disposed**. The subscriber set mutation order (before vs. after removal) is not critical for correctness but is done before the adjust call for clarity.

### How this covers all scenarios

| Scenario | Trigger |
|---|---|
| Push cell created, subscribes to initial sources | `finish_tracking` → `add_subscriber(source, reactive/effect)` → contribution=1 |
| Push cell disposed, unsubscribes from sources | `dispose_reactive`/`dispose_effect` loop → `remove_subscriber(source, reactive/effect)` → contribution=1 |
| Push cell recomputes, source set changes | `finish_tracking` → add/remove for changed sources → contribution=1 |
| Pull/hybrid memo recomputes, dep set changes | `memo_force_recompute` → add/remove for changed deps → contribution=memo.push_reachable_count |
| HybridMemo disposed | `dispose_hybrid_memo` loop → `remove_subscriber(dep, hybrid_memo)` → contribution=memo.push_reachable_count |
| Memo first computed (previously empty deps) | `memo_force_recompute` → `add_subscriber(signal, memo)` → contribution=memo.push_reachable_count |

**The memo dep-change case is the key correctness improvement over Approach A.** When memo M switches from reading `sig1` to `sig2`:
- `remove_subscriber(sig1, M)`: contribution = M.push_reachable_count (e.g. 1), `adjust_push_reachable([sig1], -1)` → sig1.count -= 1 = 0
- `add_subscriber(sig2, M)`: contribution = M.push_reachable_count (= 1), `adjust_push_reachable([sig2], +1)` → sig2.count += 1 = 1

### Consistency under interleaved operations

`push_reachable_count` and the full upstream chain are always updated atomically within a single `add_subscriber`/`remove_subscriber` call. When reactive R is disposed while memo M is in its source chain, `remove_subscriber(M, R)` calls `adjust_push_reachable([M], -1)` which decrements **both** `M.count` and all cells upstream of M (e.g. `sig1.count`). Subsequent dep changes on M then use M's already-correct count as the contribution, producing the right adjustment on the new dep. Counts never drift — the path-weight semantics are maintained exactly under all orderings of dispose and dep-change operations.

---

## The gate

### Outer gate (O(1) per changed source)

In `push_propagate.mbt`, at the top of `enqueue_push_subscribers`:

```moonbit
fn enqueue_push_subscribers(source_id : CellId) -> Unit {
  // O(1) gate: skip BFS if no push cell is downstream of this source
  if source_id.id >= 0 &&
     source_id.id < self.core.cell_ops.length() &&
     self.core.cell_ops[source_id.id].push_reachable_count() == 0 {
    return
  }
  // ... existing BFS ...
}
```

Unlike Approach A's signal-only gate, this works for all source types — signals, relations, and reactive outputs — because `push_reachable_count` lives on `CellMeta` and is uniformly accessible via `CellOps`.

### Inner BFS pruning

Within the BFS loop, skip HybridMemo and PullMemo subscribers whose count is zero:

```moonbit
HybridMemo(i) =>
  if self.pull.memos[i].meta.push_reachable_count > 0 {
    bfs_worklist.push(sub_id) // bridge only if push cells are downstream
  }
PullMemo(i) =>
  if self.pull.memos[i].meta.push_reachable_count > 0 {
    bfs_worklist.push(sub_id) // bridge only if push cells are downstream
  }
```

This prunes dead-end branches in graphs where push nodes are downstream of some but not all memo subscribers of a changed signal. The pruning is safe: if a memo's count is 0, no push cell is reachable through it, so skipping it cannot miss any notification.

**Note:** `memo.mbt` requires no code changes. The new behavior in `add_subscriber`/`remove_subscriber` is injected into the existing calls in `memo_force_recompute` automatically — the call sites in `memo.mbt` remain unchanged.

---

## Correctness

### No false negatives (critical)

When push cell R is reachable downstream of source S:
- R's creation called `add_subscriber(M, R)` (for some M), which called `adjust_push_reachable([M], 1)`, setting `M.count > 0` and `S.count > 0` (S being reachable upstream of M).
- Neither the outer gate nor inner BFS pruning skip cells with count > 0.
- Therefore, every live push cell's path is traced.

### Memo dep change soundness (critical)

The path `sig2 → M → R` becomes live only when M subscribes to sig2. That subscription happens inside `memo_force_recompute`, which is triggered from `pull_verify`, which is called during R's recompute. R's recompute is triggered by push propagation. Push propagation only runs for signals that have `push_reachable_count > 0`. But sig2 has count 0 *until* M subscribes to it — and M subscribes to it during `memo_force_recompute`, which calls `add_subscriber(sig2, M)` with contribution = M.push_reachable_count. After this call, sig2.count > 0 for any subsequent `sig2.set()`.

More precisely: before M has ever read sig2, sig2 does not affect M's output (M's compute closure was not reading sig2). So skipping BFS for sig2 when sig2.count=0 is correct — sig2's change genuinely does not reach R yet. Once M first computes with sig2 as a dep, `add_subscriber(sig2, M)` fires immediately and sig2.count becomes > 0 for all subsequent changes.

**Batch case:** If both the trigger for M's recompute and `sig2.set()` occur in the same batch, `sig2`'s `changed_at` is stamped with the current revision. When R recomputes in that batch (which calls M.get() → memo_force_recompute → add_subscriber(sig2, M)), M detects sig2's change via `changed_at > verified_at` and incorporates sig2's new value. R's output reflects both changes. This is correct: the batch revision covers all changes atomically, and R's recompute happens after `sig2.set()` has already bumped `changed_at`.

### No false positives (within a session)

Counts are decremented symmetrically: every `add_subscriber` increment is matched by a `remove_subscriber` decrement for the same subscriber. The full upstream chain is adjusted atomically via `adjust_push_reachable` in both directions. After all live push cells are disposed and all dep links are removed, every cell's count returns to 0.

---

## Testing

### Whitebox tests (`cells/push_reachable_wbtest.mbt`, new file)

- Signal with no reactive downstream: `push_reachable_count == 0`
- Signal with one direct reactive: signal.count == 1
- Signal with one reactive through a hybrid memo: signal.count == 1, memo.count == 1
- Signal with one reactive through a two-deep memo chain (`sig → memoA → memoB → reactive`): sig.count == 1, memoA.count == 1, memoB.count == 1
- **Diamond topology** (`sig → memoA → reactive`, `sig → memoB → reactive`): sig.count == 2, memoA.count == 1, memoB.count == 1; after dispose, sig.count == 0
- Reactive dispose: all counts return to 0
- Reactive source change (reads `sig1` then changes to `sig2`): `sig1.count == 0`, `sig2.count == 1`
- **Memo dep change** (reactive reads `memoA` which lazily recomputes to read `sig2` instead of `sig1`): after memoA recomputes, `sig1.count == 0`, `sig2.count == 1`
- **Reactive-to-reactive chain** (`sig → reactive1 → reactive2`): sig.count == 1, reactive1.count == 1; after reactive2 disposed, reactive1.count == 0, sig.count == 0
- **Relation-to-reactive** (reactive subscribes to a Relation): relation.count == 1; after reactive disposed, relation.count == 0
- Gate behavioral test: `signal.set()` on a signal with count == 0 does not enqueue any push entries (verify: create a reactive on a separate signal only; mutate the first signal; confirm reactive does not recompute)
- **Inner BFS pruning test (count-correctness proxy):** create `sig → memoA → reactive1` and `sig → memoB → reactive2`. Verify sig.count == 2, memoA.count == 1, memoB.count == 1. Dispose reactive2. Verify sig.count == 1, memoB.count == 0. Call `sig.set(new_value)`; verify reactive1 still fires with the correct value (the live branch still propagates). This test verifies that the count correctly reaches 0 on the pruned branch and that the live branch is unaffected. Direct BFS traversal is an internal implementation detail and is validated by the benchmark.

### Benchmarks

Re-run `cells/push_efficiency_bench_test.mbt` after implementation. Target: mixed-graph benchmarks match baseline (≤ 0.05 µs for 100 and 1000 hybrid subs with distant reactive).

### Regression

All 323 existing tests must pass unchanged.

---

## Files changed

| File | Change |
|---|---|
| `cells/cell_ops.mbt` | Add `push_reachable_count : Int` to `CellMeta`; add `push_reachable_count(Self) -> Int` to `CellOps` with default impl |
| `cells/runtime.mbt` | Add `collect_reachable_cells`, `adjust_push_reachable`, `push_contribution` helpers; extend `add_subscriber`/`remove_subscriber` to propagate count changes |
| `cells/push_propagate.mbt` | Add outer O(1) gate in `enqueue_push_subscribers`; add inner BFS pruning for zero-count HybridMemo/PullMemo subscribers |
| `cells/push_reachable_wbtest.mbt` (new) | Whitebox tests for count maintenance and gate behavior |
| `cells/push_efficiency_bench_test.mbt` | Verify benchmark improvement |

**Files requiring constructor literal updates** (MoonBit requires every struct field to be set at construction, so `push_reachable_count: 0` must be added to each `CellMeta` literal):
- `cells/memo.mbt` — add `push_reachable_count: 0` to the `CellMeta` literal in `Memo::new` / `HybridMemo::new`; `memo_force_recompute` already calls `add_subscriber`/`remove_subscriber` so count maintenance is injected automatically
- `cells/push_effect.mbt` — add `push_reachable_count: 0` to `PushEffectData.meta` literal; `CellOps` default covers `push_reachable_count` reads
- `cells/push_reactive.mbt` — same as above for `PushReactiveData.meta`
- `cells/datalog_relation.mbt`, `cells/datalog_functional_relation.mbt` — add `push_reachable_count: 0` to `RelationData.meta` and `FunctionalRelationData.meta` literals
- `cells/runtime.mbt` — add `push_reachable_count: 0` to the `PullSignalData.meta` literal in `new_signal_id`
- `cells/cell_ref_wbtest.mbt` — update the test `PullSignalData` literal too

The `.mbti` interface file for the `cells` package will regenerate (run `moon info`) to reflect the new `CellMeta` field and `CellOps` method. No public API changes — `push_reachable_count` is a private implementation detail.
