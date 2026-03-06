# Defect and Structural Analysis Report: `dowdiness/incr`

## 1. Project Structure Overview

The project is a Salsa-inspired incremental computation library with a hybrid push-pull architecture. It has seven cell kinds stored in Structure-of-Arrays (SoA) layout on a central `Runtime`, with type erasure via captured closures. The codebase comprises ~2,700 lines of implementation and ~3,500 lines of tests. Entry points are `Signal::set` (writes), `Memo::get`/`HybridMemo::get` (reads), `push_propagate_from` (eager propagation), and `Runtime::fixpoint` (Datalog evaluation).

---

## 2. Confirmed Defects

### 2.1 Re-entrant `push_propagate_from` via Effect/Reactive compute functions

**Location**: `signal.mbt:189-207` (non-batch `set_unconditional`) and `propagate.mbt:209,241` (reactive compute / effect execute)

**Observable behavior**: When `Signal::set_unconditional` is called outside a batch, it calls `push_propagate_from` at line 199. Inside `push_propagate_from`, reactive compute functions (`propagate.mbt:209`) and effect execute functions (`propagate.mbt:241`) run user-provided closures. If any of these closures calls `signal.set()` on another signal, `batch_depth` is 0 at this point, so `set_unconditional` is called, which calls `push_propagate_from` **re-entrantly**.

**Why this is a defect**: While the priority queue and BFS worklist are local to each `push_propagate_from` call (so they don't corrupt), the shared mutable state `hybrid_dirty` is a problem. The inner call clears `hybrid_dirty` at `propagate.mbt:253`. Any entries accumulated by the outer call's `enqueue_push_subscribers` before the re-entrant call are lost. More critically, `advance_revision` during the inner call shifts `current_revision` underneath the outer propagation, causing `reactive.changed_at = self.current_revision` (`propagate.mbt:219`) to stamp with a newer revision than expected. The dirty flag interactions are also subtle: the inner call may clear dirty on nodes that the outer call has queued but not yet processed.

**Contrast with `commit_batch`**: The batch path explicitly guards against this at `runtime.mbt:804` by elevating `batch_depth` before invoking callbacks. No equivalent guard exists for the non-batch push propagation path.

**Scenario**: Create Signal S1, Effect E that reads S1 and conditionally sets Signal S2, and Reactive R that reads S2. When S1 changes outside a batch, `push_propagate_from` runs E, E calls `S2.set()`, which triggers a nested `push_propagate_from`. R may be processed by the inner call, then the outer call skips it (dirty already cleared), or it may be processed twice with inconsistent revision stamps.

**Certainty**: Likely. The conditions are reachable if a user writes an effect that updates a signal. The exact behavioral consequence depends on the graph topology.

---

### 2.2 `cell_ops` retains dangling reference after push cell disposal with slot reuse

**Location**: `reactive.mbt:117-123` (slot reuse) and `runtime.mbt:1029-1038` (disposal)

**Observable behavior**: When a `PushReactive` is disposed (`runtime.mbt:1029`), `cell_index[cell_id.id]` is set to `Disposed`, and the SoA slot is cleared in-place. The comment at line 1031 says "Both push_reactives[idx] and cell_ops[cell_id.id] reference the same heap object." When a new reactive reuses the same SoA index (`reactive.mbt:117-118`: `rt.push_reactives[reactive_idx] = new_data`), the array slot is **replaced** with a new `PushReactiveData` object. However, `cell_ops[old_cell_id.id]` still holds a trait reference to the **old** (cleared) object — it is NOT updated to the new object.

**Why this is a defect**: The comment at `runtime.mbt:1031` claims that mutations via `push_reactives[idx]` are visible through `cell_ops[cell_id.id]`. This is true **during disposal** (both reference the same heap object, and mutations like `reactive.compute = ...` modify it in place). But after **slot reuse** at `reactive.mbt:118`, the array slot holds a NEW object. `cell_ops[old_cell_id.id]` becomes a stale reference to the cleared object. Functions that access cells via `cell_ops` without checking `cell_index` first (e.g., `get_changed_at`, `get_durability`, `get_subscribers`, `remove_subscriber`, `add_subscriber`) would silently operate on stale data if called with the old `CellId`.

**Mitigation**: `cell_index[old_id]` is `Disposed`, so high-level entry points like `pull_verify` that check `cell_index` first would catch this. But internal helpers like `remove_subscriber` (`runtime.mbt:414-427`) only check runtime_id and bounds, not `cell_index`. A stale `CellId` from a disposed reactive, if retained in a dependency list or subscriber set, could pass those checks.

**Certainty**: Possible. Requires a stale `CellId` to survive in a subscriber set or dependency list after disposal. The disposal code removes the cell from its sources' subscriber sets (`runtime.mbt:1026-1028`), but does NOT scan other cells' dependency lists for references to the disposed cell. If a memo recorded a dependency on the reactive (via `Reactive::get` -> `record_dependency`), that dependency would remain stale.

---

## 3. High-Risk Areas and Potential Bugs

### 3.1 Mutual recursion between `pull_verify` and `pull_verify_hybrid` defeats the explicit stack

**Location**: `verify.mbt:119-130` (`pull_verify` calls `pull_verify_hybrid`) and `verify.mbt:252-262` (`pull_verify_hybrid` calls `pull_verify`) and `verify.mbt:278-288` (`pull_verify_hybrid` calls itself recursively)

**Observation**: `pull_verify` uses an explicit `PullVerifyFrame` stack to avoid deep call-stack recursion. However, when it encounters a `HybridMemo` dependency, it calls `pull_verify_hybrid` via actual function call recursion. `pull_verify_hybrid` in turn may call `pull_verify` for `PullMemo` deps, or call itself recursively for `HybridMemo` deps. This creates mutual recursion that can grow the call stack proportionally to the depth of hybrid->memo->hybrid chains.

**Risk**: A dependency graph with a deep chain of alternating HybridMemos and PullMemos would produce a call stack of depth proportional to the chain length. The explicit stack design was meant to avoid this.

**Certainty**: Likely, given a sufficiently deep graph. The practical impact depends on MoonBit's WASM call stack limit.

### 3.2 Stale memo dependency on a disposed reactive causes silent incorrect verification

**Location**: `verify.mbt:102-106`

**Observation**: When `pull_verify` encounters a `PushReactive` or `PushEffect` dependency, it checks `changed_at > memo.verified_at`. But if the reactive was disposed, `cell_index[dep_id.id]` is `Disposed`, and `pull_verify` hits the `Disposed` arm at line 131:

```
Disposed => abort("pull_verify: dependency has been disposed")
```

This aborts the program. A memo that recorded a dependency on a reactive (via `Reactive::get()` during computation) and then the reactive was disposed before the memo's next verification would crash.

**Risk**: This is by design (abort indicates a programming error — the memo's compute function should not depend on a disposed cell). However, there is no mechanism to automatically invalidate or clean up such stale dependencies when a reactive is disposed.

**Certainty**: Certain, given the scenario. Whether it's classified as a "bug" depends on API contract expectations.

### 3.3 `collect_in_progress_path` is O(n) and produces imprecise cycle paths

**Location**: `runtime.mbt:256-269`

**Observation**: `collect_in_progress_path` scans ALL `pull_memos` and `hybrid_memos` to find those with `in_progress = true`. This is O(total-memos) regardless of cycle length. It's called from `pull_verify` line 82 (root already in_progress) and `pull_verify_hybrid` line 238 (root already in_progress). In contrast, the stack-based path at `verify.mbt:149-154` is O(cycle-depth) and produces the exact cycle path.

**The path from `collect_in_progress_path` is imprecise**: it returns ALL currently in-progress memos, which may include memos from entirely unrelated concurrent verification paths (if `pull_verify` was called re-entrantly via `force_recompute`). These extra memos would pollute the cycle error path.

**Certainty**: Certain behavior, possible impact (matters when nested verification creates multiple simultaneous in-progress memos).

---

## 4. Edge Cases and Reliability Concerns

### 4.1 `hybrid_dirty` is accumulated but never consumed

**Location**: `propagate.mbt:167-168` (population) and `propagate.mbt:253` (clearing)

**Observation**: In `enqueue_push_subscribers`, when a `HybridMemo` is dirtied, its CellId is pushed to `self.hybrid_dirty`. At the end of `push_propagate_from`, `self.hybrid_dirty.clear()` is called. But `hybrid_dirty` is never read by any function — not in `push_propagate_from`, not anywhere else in the codebase.

The dirty flag on `HybridMemoData` itself IS used (checked by `HybridMemo::get`). The `hybrid_dirty` array on `Runtime` appears to be vestigial — possibly intended for a future batch-level dirty tracking feature but currently dead state.

**Impact**: Minor. The array allocates and clears on every push propagation wave without serving any purpose. Not a correctness issue.

**Certainty**: Certain (confirmed via search — no reads of `hybrid_dirty` outside these two sites).

### 4.2 Memo `force_recompute` tracking frame not cleaned up on user compute abort

**Location**: `memo.mbt:247-249`

```moonbit
self.rt.push_tracking(self.cell_id)
let new_value = (self.compute)()
let (new_deps, new_seen) = self.rt.pop_tracking()
```

**Observation**: If `(self.compute)()` — the user's compute function — calls `abort()` (e.g., via `some_memo.get()` which aborts on cycle), the tracking frame is never popped and `in_progress` is never cleared. Since MoonBit's `abort()` terminates the program, this is not a runtime issue in production. However, if the test harness catches panics (MoonBit `test "panic ..."` tests), the tracking stack and `in_progress` flags may leak into subsequent tests within the same runtime.

**Mitigation**: The tests create fresh `Runtime` instances, so leaked state is isolated. The CLAUDE.md notes this with `current_computing_runtime_id` reset in cross-runtime guards. But `in_progress` on `PullMemoData` is not reset.

**Certainty**: Possible, depends on test runner behavior with panic tests sharing runtime instances.

### 4.3 `Relation::insert` outside fixpoint accumulates delta facts invisible to `contains`/`iter`

**Location**: `relation.mbt:119-135` and `relation.mbt:142-145`

**Observation**: `insert()` outside fixpoint adds facts to `delta`. But `contains()` and `iter()` only query `current`:

```moonbit
pub fn[T : Hash + Eq] Relation::contains(self : Relation[T], value : T) -> Bool {
  self.record_read_dependency()
  self.current.val.contains(value)
}
```

Facts in `delta` are invisible until `fixpoint()` runs and drains them. If `fixpoint()` is never called after insertion, the facts are permanently stuck in `delta`. There is no public API to inspect delta contents besides `delta_iter()`, and no warning or error if facts are inserted but never materialized.

**Impact**: This is likely intentional API design (delta is a staging area), but it could confuse users who insert facts and then immediately query the relation without calling `fixpoint()`.

**Certainty**: Certain behavior, uncertain whether it's a defect or intentional design.

### 4.4 `fixpoint` convergence depends on rule body correctness

**Location**: `fixpoint.mbt:35-37`

```moonbit
for rule in self.rules {
  (rule.apply_delta)()
}
```

**Observation**: If a rule's `apply_delta` closure inserts facts directly into `delta` (instead of `staged_delta` via `Relation::insert`), the semi-naive convergence guarantee breaks. `Relation::insert` correctly routes to `staged_delta` during fixpoint (`relation.mbt:126-133`), but a rule could bypass `insert` and directly modify the `Ref[HashSet]` if it captured the `Relation` struct.

However, since `current`, `delta`, and `staged_delta` are `priv` fields on `Relation`, external code cannot access them. The only way to add facts is through `insert()`, which does route correctly. So this is not exploitable through the public API.

**Certainty**: Not a defect (private field access prevents bypass).

### 4.5 No cycle detection in push propagation graph

**Location**: `propagate.mbt:137-254`

**Observation**: The push propagation BFS has no cycle detection. If a `PushReactive`'s compute function reads a cell that transitively subscribes back to itself, the `enqueue_push_subscribers` BFS could loop. However, the dirty flag guard (`if not(self.push_reactives[i].dirty)`) prevents re-enqueueing an already-dirty node, and the topological level ordering means a node is only processed once per wave. After processing, `dirty = false`, so re-dirtying would enqueue it again at its (now-current) level.

A true cycle (R1 reads R2, R2 reads R1) would cause infinite recomputation: R1 changes -> R2 re-enqueued -> R2 changes -> R1 re-enqueued -> ... The level ordering prevents this IF levels are set correctly (each level is strictly greater than sources' levels). With a cycle, `recompute_level` would not converge. But `recompute_level` computes from current sources after each compute, and the `propagate_level_change` BFS would also loop.

**Risk**: No detection means infinite loop on cyclic push graphs. The pull side has explicit cycle detection (`in_progress` flag); the push side does not.

**Certainty**: Certain absence of cycle detection. Practical impact depends on whether users can construct cyclic push graphs.

---

## 5. Refactoring Opportunities

### 5.1 Unify subscriber link maintenance between `Memo::force_recompute` and `Runtime::finish_tracking`

**Location**: `memo.mbt:254-278` vs `runtime.mbt:987-1012`

**Observation**: `Memo::force_recompute` performs an inline subscriber diff that reuses the `seen` HashSet from `pop_tracking`, avoiding an extra allocation. `Runtime::finish_tracking` performs the same diff but constructs its own `old_seen`/`new_seen` HashSets. `HybridMemo::force_recompute` (`hybrid_memo.mbt:160-179`) duplicates the inline pattern from `Memo::force_recompute`.

Three copies of the same algorithm exist. The only difference is the optimization in `Memo::force_recompute` that reuses the `seen` set. This could be unified by making `finish_tracking` accept an optional pre-built `new_seen` set, or by having all cell types call a single subscriber-diff function.

**Improvement**: Reduces the surface area for bugs in subscriber maintenance. Currently, a fix to one copy must be manually replicated to the others.

### 5.2 Extract `pull_verify_hybrid` logic into the `PullVerifyFrame` stack

**Location**: `verify.mbt:219-305`

**Observation**: `pull_verify` uses an explicit stack for PullMemo deps but falls back to recursive function calls for HybridMemo deps. This could be unified by extending `PullVerifyFrame` to also handle HybridMemo entries (adding a `cell_kind` discriminant). This would eliminate the mutual recursion described in section 3.1 and provide consistent stack-depth behavior.

**Improvement**: Eliminates call-stack overflow risk for deep hybrid/memo chains. Makes the verification algorithm uniformly iterative.

### 5.3 Remove `hybrid_dirty` field from Runtime

**Location**: `runtime.mbt:93`, `propagate.mbt:168,253`

**Observation**: As documented in section 4.1, `hybrid_dirty` is dead state. Removing it reduces confusion for contributors who might expect it to serve a purpose.

### 5.4 Add `cell_index` Disposed check to low-level `cell_ops`-based helpers

**Location**: `runtime.mbt:275-295` (`get_changed_at`, `get_durability`)

**Observation**: These functions validate runtime_id and bounds but do not check `cell_index` for `Disposed`. Adding a `Disposed` check (or a unified `validate_cell_id` helper) would make stale CellId access fail loudly rather than silently returning cleared data.

---

## 6. Structural Design Issues

### 6.1 `RuleData.input_relations` and `output_relations` are stored but never read

**Location**: `rule.mbt:11-12`

```moonbit
input_relations : Array[CellId]
output_relations : Array[CellId]
```

**Observation**: These fields are written during `Runtime::new_rule` (lines 68-69) and validated against `cell_index` (line 57-61), but never subsequently read by any runtime logic. The compiler warnings confirm this. They are presumably reserved for future use (selective rule application, dependency analysis), but currently add dead weight to every `RuleData` allocation.

### 6.2 Type-erased compute closure and `force_recompute` both set `verified_at` and `in_progress`

**Location**: `verify.mbt:181,192` vs `memo.mbt:294-295`

**Observation**: When `pull_verify` calls `(memo.compute)()`, the underlying `force_recompute` sets `cell.verified_at` and `cell.in_progress = false`. Then `pull_verify` sets them again at lines 181 and 192. The double-write is harmless (same values) but indicates unclear ownership of these fields during verification.

The root cause is that `force_recompute` is designed to be a self-contained recomputation path (called both from `get_result` first-compute path and from `pull_verify`). When called from `pull_verify`, the ownership split is ambiguous: `force_recompute` assumes full responsibility; `pull_verify` also assumes it.

### 6.3 `push_propagate_from` is a 120-line function with a nested closure, BFS, priority queue, level recalculation, subscriber diffing, and disposal checks

**Location**: `propagate.mbt:129-254`

This function handles seeding (via nested BFS closure), topological processing, level changes, subscriber maintenance, early cutoff, disposal checking, and dirty flag management. The nested `enqueue_push_subscribers` closure captures `update_queue` and `bfs_worklist` from the enclosing scope, creating implicit coupling.

Breaking this into smaller functions (e.g., `process_reactive`, `process_effect`, and making `enqueue_push_subscribers` a method on Runtime taking the queue as a parameter) would improve readability and testability.

---

## 7. Uncertain Observations

### 7.1 Whether MoonBit struct assignment replaces the heap reference or copies fields

**Relevant to**: Section 2.2 (slot reuse after disposal)

The analysis assumes `rt.push_reactives[reactive_idx] = new_data` replaces the array slot's reference with a new object, leaving old references dangling. If MoonBit semantics instead copy fields into the existing object (like a value type), then `cell_ops[old_id]` would see the new data. The comment at `runtime.mbt:1031` ("both reference the same heap object") suggests reference semantics, confirming the first interpretation. But this cannot be 100% confirmed without MoonBit language specification access.

### 7.2 Whether `@priority_queue.PriorityQueue` is a max-heap or min-heap

**Relevant to**: `propagate.mbt:1-20`

The code negates levels to simulate min-heap behavior (`neg_level: -level`). The comment at line 4 says "max-heap." If the priority queue is actually a min-heap, the negation would invert the ordering, processing nodes in the wrong (bottom-up instead of top-down) order, causing glitches. The Compare impl at lines 18-19 compares `neg_level` directly, which with a max-heap gives correct topological (level-ascending) order.

### 7.3 Thread safety of `next_runtime_id` and `current_computing_runtime_id`

The code acknowledges this at `runtime.mbt:17-21`: "MoonBit currently targets WebAssembly (inherently single-threaded) and a single-threaded native runtime, so a plain `Ref[Int]` is safe here." If parallel execution is introduced, these become data races. This is an acknowledged future concern, not a current defect.

---

## 8. Summary of Most Important Findings

| # | Finding | Severity | Certainty |
|---|---------|----------|-----------|
| 2.1 | Re-entrant `push_propagate_from` when effect/reactive compute writes a signal outside batch | High | Likely |
| 2.2 | `cell_ops` retains stale reference after push cell disposal + slot reuse | Medium | Possible |
| 3.1 | Mutual recursion `pull_verify` <-> `pull_verify_hybrid` defeats explicit stack | Medium | Likely |
| 3.2 | Disposed reactive in memo's dependency list causes abort on next verify | Medium | Certain |
| 4.1 | `hybrid_dirty` array is dead state (accumulated, never read) | Low | Certain |
| 4.5 | No cycle detection in push propagation graph | Medium | Certain |
| 5.1 | Subscriber diff logic duplicated 3 times | Low | Certain |
| 6.2 | `verified_at`/`in_progress` set redundantly by both `force_recompute` and `pull_verify` | Low | Certain |

The most actionable finding is **section 2.1** — the re-entrant push propagation risk. The `commit_batch` path explicitly guards against this (`batch_depth` elevation at `runtime.mbt:804`), but the non-batch `Signal::set_unconditional` path does not. A similar guard (or documented prohibition against signal writes inside reactive/effect compute functions) would close this gap.
