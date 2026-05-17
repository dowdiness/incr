# T1b (`MemoCommitPhase`) — Implementation Plan

> **Status:** Active. To be marked Complete and moved to `docs/archive/plans/` when the PR merges.
>
> **Revision history:**
> - 2026-05-17 v1: Initial plan
> - 2026-05-17 v2: Reworked after Codex pre-implementation review identified six hard correctness issues. Trait placement corrected (cells/, not kernel/). Phase 2 collapsed into one atomic switchover. Hook timing moved post-epilogue. Push-path inventory corrected. Behavior-preservation rule added for non-memo frames.
> - 2026-05-17 v3: Second Codex round flagged three additional issues. (a) Hook contract amended in T1b ADR — implementors must not call user code inline; buffer-and-flush pattern documented (load-bearing for the event-tap follow-up, not for this plan since accumulator hook calls no user code). (b) `memo: no-accumulator recompute fanout` bench moved from Phase 3 to Phase 1 (Task 4.1) so the perf-gate at Task 7.1 has a pre-switchover baseline. (c) Event-observation ADR fixed (kernel-placement text remnants).
> - 2026-05-17 v4 (this revision): Third Codex round caveats. (a) Drain protocol in event ADR expanded to cover all `force_recompute` callers (not just `recompute_inner`) and given a `draining : Bool` reentry guard with tail-flush loop. (b) T1b ADR §Scope rewritten to remove stale `cells/internal/kernel/` references. (c) Plan Task 4.3 added — pre-T1b reference for the new no-accumulator bench via cherry-pick onto main, so Phase 1 empty-dispatch overhead is verified on that row too.

> **For agentic workers:** REQUIRED SUB-SKILL: Use `superpowers:executing-plans` or `superpowers:subagent-driven-development` to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking. **Pause for Codex review at the three gates marked ⚠️ in the task list.**

**Goal:** Refactor the accumulator's three named commit-path calls in `cells/memo.mbt` into trait-dispatched hooks via a new `priv MemoCommitPhase` trait, without changing public API or behavior. After this plan: the accumulator is one registered implementor; future cross-cutting concerns (e.g., visualization event tap per the follow-up ADR) register additional implementors.

**Authoritative spec:** [`docs/decisions/2026-05-17-t1b-memo-commit-phase.md`](../decisions/2026-05-17-t1b-memo-commit-phase.md) (amended 2026-05-17 post-Codex). If this plan and the ADR disagree, **the ADR wins** — file a follow-up to update the plan.

**Tech Stack:** MoonBit 0.9.2+, `moon` build system, MoonBit `internal` package visibility. No new external dependencies.

**Architecture (post-Codex):**
- **Trait file lives in `cells/`, not `cells/internal/kernel/`** — the trait methods take `rt : Runtime`, and kernel cannot import `cells/` (engine-isolation invariant #4, `scripts/check-engine-isolation.sh`). Mirrors the `CellLifecycle` precedent.
- **`commit_hooks` field lives on `Runtime`, not `RuntimeCore`** — same reason.
- **`accumulator_commit_hook` typed field on `Runtime`** — push paths in `cells/accumulator.mbt` reach the hook via typed field, not array-index downcast. The same object is also registered in `commit_hooks` for trait-polymorphic iteration.
- **Shape (2)**: `accumulator_reads` and `touched_accumulator_slots` move **off** `ActiveQuery` and **onto** `AccumulatorCommitHook.active : HashMap[CellId, RecomputeState]`.
- **`after_success` fires AFTER the cell-level epilogue** — `changed_at` / `verified_at` / `has_been_computed` / `in_progress = false` are all set when the hook runs. Backdating is detectable.
- **Forward-order dispatch on both success and abort** — explicit, contracted.

**Worktree:** Branch `refactor/t1b-memo-commit-phase` in `.worktrees/t1b-memo-commit-phase`. All commands assume this is the current directory. Spawn via `git worktree add` from main.

**Safety net:**
- Existing 508+ test suite (`moon test`). Three new whitebox invariant tests added: hook dispatch order, non-memo-frame preservation, nested-recompute correctness.
- 41 accumulator-specific tests in `cells/accumulator_wbtest.mbt` + `cells/accumulator_restore_bench_wbtest.mbt`.
- Lambda type-checker driver coverage in loom (retroactive — `loom/examples/lambda` must still build cleanly after this lands, but its tests run in loom not incr).
- Benchmark gate: commit-path microbenches in `tests/bench_test.mbt` within ±5% of pre-T1b baseline. **A new memo-no-accumulator benchmark must be added** to catch overhead in workloads that get no benefit from the hook.

**Per-step verification contract** (run after each task):

```bash
moon check                          # zero errors
moon test                           # passed: 508+, failed: 0
moon info && moon fmt               # regenerate .mbti, format
git diff --exit-code pkg.generated.mbti tests/pkg.generated.mbti types/pkg.generated.mbti pipeline/pkg.generated.mbti cells/pkg.generated.mbti
                                    # exit 0 — no public API drift expected
scripts/check-engine-isolation.sh   # must pass
```

If `moon check` fails, fix the import or visibility error before proceeding — do not commit in a red state.

---

## File map

**Files created:**
- `cells/memo_commit_phase.mbt` — `priv trait MemoCommitPhase` (lives in `cells/`, **not** `cells/internal/kernel/`)
- `cells/accumulator_commit_hook.mbt` — `priv struct AccumulatorCommitHook` + `impl MemoCommitPhase`
- `cells/accumulator_commit_hook_wbtest.mbt` — three invariant tests (dispatch order, non-memo-frame preservation, nested recompute)

**Files modified:**
- `cells/runtime.mbt` — add `priv accumulator_commit_hook : AccumulatorCommitHook` field + `priv mut commit_hooks : Array[&MemoCommitPhase]` field; `Runtime::new` constructs the hook once and uses the same ref in both
- `cells/memo.mbt` — three dispatch loops in `memo_force_recompute` (Phase 1, empty list); switch from named calls to hook-driven (Phase 2, atomic)
- `cells/accumulator.mbt` — delete the three free functions (`memo_snapshot_accumulator_contributions`, `memo_restore_on_abort`, `memo_commit_accumulator_phase`); redirect push paths at lines 464, 540, 581 to write through `self.rt.accumulator_commit_hook.active[recomputing_cell]` with the behavior-preservation rule below
- `cells/internal/kernel/state.mbt` — remove `accumulator_reads` + `touched_accumulator_slots` from `ActiveQuery`; remove `ensure_*` helpers; remove `None` initializers (Phase 2)
- `cells/accumulator_wbtest.mbt` — migrate any test that reads `ActiveQuery.accumulator_reads` / `touched_accumulator_slots` directly
- `tests/bench_test.mbt` — add `memo: no-accumulator recompute fanout` bench (**Phase 1, Task 4.1** — must land before Phase 2 to establish a pre-switchover baseline)
- `docs/design/internals.md` — update "Accumulator" section to describe trait-dispatched hooks; document the `MemoCommitPhase` extension point (without implementation specifics per project doc convention)
- `CLAUDE.md` — Package Map adds `cells/memo_commit_phase.mbt` + `cells/accumulator_commit_hook.mbt`

**Files deleted:** none.

**Behavior preservation rule (load-bearing, applies in Phase 2):**

| Site | Current behavior | Redirect under shape (2) |
|---|---|---|
| `cells/accumulator.mbt:464` (`Accumulator::push`, inside `ensure_touched_accumulator_slots`) | Aborts at `:451` if frame is not Memo/HybridMemo; writes to frame's lazy `touched_accumulator_slots` | Look up `self.rt.accumulator_commit_hook.active[m_id]`; if absent, abort with same message |
| `cells/accumulator.mbt:540` (`Memo::accumulated`, inside `ensure_accumulator_reads`) | `match top_active_query()` — `Some(frame)` writes to lazy `accumulator_reads`; **`None` silently no-ops** | Look up `active[cell_id_of_top_frame]`; if frame absent OR entry absent, **silently no-op** |
| `cells/accumulator.mbt:581` (`Memo::accumulated_result`, inside `ensure_accumulator_reads`) | Same as `:540` — `Some(frame)` writes; `None` silently no-ops | Same as `:540` — silently no-op when frame or entry absent |

`Memo::accumulated_peek` at lines 474–499 is untracked and **does not** call `ensure_accumulator_reads`. **Not a redirect site.** Verified by reading the function body.

The non-memo-frame case is real: `Memo::accumulated` / `accumulated_result` can be called from inside a push-reactive or effect compute frame. Today's behavior is silent no-op (lazy-alloc on a frame whose `pop_tracking` discards). Under shape (2), the equivalent is "no `active[cell]` entry → no write." Same observable behavior.

---

## Phase 1: Trait + dispatch loops, hook NOT yet registered (no behavior change)

This phase adds the scaffolding with empty dispatch. The OLD named calls in `memo_force_recompute` stay intact. Behavior is byte-identical.

### Task 1: Codex Gate 1 — trait placement + signatures + field placement ⚠️

- [ ] **Step 1.1: Re-read the amended T1b ADR end-to-end.**

In particular, §"Trait shape", §"Dispatch", §"Hook timing", §"Accumulator refactor". The plan implements those decisions; do not improvise.

- [ ] **Step 1.2: Confirm trait placement against engine-isolation invariants.**

Read `scripts/check-engine-isolation.sh` and confirm invariant #4: "kernel is one-way — engines and shared must not import kernel, only `cells/*.mbt` may." Confirm `cells/runtime.mbt:30` shows `CellLifecycle` field on `Runtime` for the same reason. The trait file must live in `cells/`.

- [ ] **Step 1.3: Submit Gate 1 review to Codex.**

Question: "Confirm the trait shape, file placement, and Runtime field placement against the amended ADR. The trait is `priv MemoCommitPhase` in `cells/memo_commit_phase.mbt` (NOT kernel), with three methods taking `(self, rt : Runtime, cell_id : CellId) -> Unit`. `commit_hooks : Array[&MemoCommitPhase]` field on `Runtime`. Are there issues I haven't surfaced?"

Apply Codex's feedback. If a structural objection lands, update the ADR before proceeding.

### Task 2: Create the trait file

- [ ] **Step 2.1: Create `cells/memo_commit_phase.mbt`.**

```moonbit
///|
/// Cross-cutting commit-phase observer for pull-mode memo recomputes.
///
/// Implementors register with `Runtime::commit_hooks` (insertion order)
/// and observe each memo recompute's lifecycle:
/// - `before_recompute` fires before the tracking frame is pushed
/// - `after_abort` fires inside the catch arm, before pop_tracking
/// - `after_success` fires AFTER the cell-level epilogue is complete
///   (changed_at / verified_at / has_been_computed all set)
///
/// Implementors manage their own per-cell state (no Snapshot type in the
/// trait). For each `before_recompute` there is exactly one matching
/// `after_success` or `after_abort` for the same `cell_id`.
///
/// Dispatch is forward-order on BOTH success and abort. The first
/// registered hook always fires first regardless of branch.
///
/// This trait lives in `cells/` (not `cells/internal/kernel/`) because
/// its methods take `rt : Runtime`, and kernel cannot import `cells/`.
/// Mirrors the `CellLifecycle` precedent at `cells/runtime.mbt:30`.
priv trait MemoCommitPhase {
  fn before_recompute(self : Self, rt : Runtime, cell_id : CellId) -> Unit
  fn after_success(self : Self, rt : Runtime, cell_id : CellId) -> Unit
  fn after_abort(self : Self, rt : Runtime, cell_id : CellId) -> Unit
}
```

### Task 3: Add `commit_hooks` field + empty dispatch loops

- [ ] **Step 3.1: Modify `cells/runtime.mbt::Runtime` struct.**

Add field next to `cell_lifecycle`:

```moonbit
priv mut commit_hooks : Array[&MemoCommitPhase]
```

Initialize to `[]` in `Runtime::new`. **Do not register any hook yet.**

- [ ] **Step 3.2: Add three dispatch loops in `cells/memo.mbt::memo_force_recompute`.**

The placement reflects the amended ADR's hook timing. **Both the new dispatch loops AND the existing named calls stay in this phase.** Empty `commit_hooks` makes the loops no-ops.

```moonbit
fn[T] Runtime::memo_force_recompute(...) -> Result[T, CycleError] raise Failure {
  let cell = self.get_memo_data(cell_id)
  if cell.in_progress { return Err(...) }
  cell.in_progress = true

  // 1. BEFORE — dispatch loop (empty in Phase 1) ←←← NEW
  for hook in self.commit_hooks { hook.before_recompute(self, cell_id) }
  // KEEP the existing named call (deleted in Phase 2):
  let prev_contributions = memo_snapshot_accumulator_contributions(self, cell_id)

  let old_deps = cell.dependencies
  @kernel.push_tracking(self.core, cell_id)
  let new_value = compute_fn() catch {
    e => {
      // 2. ABORT — dispatch loop (empty in Phase 1) ←←← NEW
      for hook in self.commit_hooks { hook.after_abort(self, cell_id) }
      // KEEP the existing named call (deleted in Phase 2):
      memo_restore_on_abort(self, cell_id, prev_contributions)
      let _ = @kernel.pop_tracking_full(self.core)
      cell.in_progress = false
      raise e
    }
  }

  let query = @kernel.pop_tracking_full(self.core)
  // KEEP the existing accumulator commit (deleted in Phase 2):
  memo_commit_accumulator_phase(
    self, cell, cell_id, prev_contributions,
    query.touched_accumulator_slots, query.accumulator_reads,
  )

  // ... existing cell-level epilogue (unchanged):
  //   diff_and_update_subscribers, cell.dependencies = new_deps,
  //   compute_durability, value_changed check, changed_at update,
  //   verified_at, has_been_computed, in_progress = false ...

  // 3. SUCCESS — dispatch loop (empty in Phase 1) — AFTER the epilogue ←←← NEW
  for hook in self.commit_hooks { hook.after_success(self, cell_id) }

  Ok(new_value)
}
```

Note: in Phase 1, the *accumulator commit* (`memo_commit_accumulator_phase`) is still in its OLD location (before the epilogue), because the named call is unchanged. The new dispatch loop is at the *new* location (after the epilogue). When Phase 2 deletes the named call, the accumulator's work moves into the hook impl which fires from the new location.

- [ ] **Step 3.3: Run verification contract.**

`moon check && moon test && scripts/check-engine-isolation.sh`. Zero failures expected — three empty loops added, behavior unchanged.

### Task 4: Add no-accumulator bench + Phase 1 bench-gate (establishes pre-switchover baseline)

This task adds a microbenchmark that exercises the path most at risk of regression: memo recompute fanout with no accumulators touched. The bench must land **before** the Phase 2 switchover so we have a pre-switchover number to compare against. Codex flagged this in the second review (P3).

- [ ] **Step 4.1: Add `tests/bench_test.mbt` row: `memo: no-accumulator recompute fanout`.**

Construct: one input signal feeding ~50 memos, each memo doing pure-pull recompute (no `Accumulator::push`, no `Memo::accumulated`). Bump the signal repeatedly and measure the per-recompute cost.

Land this bench as part of the Task 4 commit *while in Phase 1* — empty dispatch loops in place, no hook registered. The number recorded here is the **pre-switchover** baseline.

- [ ] **Step 4.2: Run `moon bench --release` and capture all relevant rows.**

Record numbers for:
- `memo: create-dispose cycle`
- `memo: deep chain 100 levels stale`
- `memo: wide fanout 1→50 stale`
- **`memo: no-accumulator recompute fanout`** (new — Phase 1 baseline)
- `push: propagation 100 live reactives` (should be unaffected)

Each empty-loop adds one length-check + one branch. Expected overhead vs. pre-T1b (main): <1 ns per memo recompute, within ±5%.

- [ ] **Step 4.3: Capture a pre-T1b reference for the new bench specifically.**

The new `memo: no-accumulator recompute fanout` row didn't exist in pre-T1b main, so the Phase 1 number alone tells us nothing about empty-dispatch overhead. To establish that empty-dispatch is within budget on this path:

Option A (preferred): cherry-pick **just the bench-row addition** onto pre-T1b main in a scratch worktree, run `moon bench --release`, capture the pre-T1b number for that row. Discard the cherry-pick. The difference (Phase 1 vs. pre-T1b cherry-pick) is the empty-dispatch overhead and must be within ±5%.

Option B (fallback): if the cherry-pick is awkward, document the absolute Phase 1 number with the analytical expectation ("X empty for-loop iterations per recompute, expected overhead <Y ns"), and let Codex Gate 1 / Gate 2 reviewers accept the budget.

- [ ] **Step 4.4: If commit-path benches degrade > 5% vs. pre-T1b main on existing rows, OR if the new row's Phase 1 overhead exceeds 5% via Option A, add a fast-path.**

Add `commit_hooks.is_empty()` guard around each dispatch loop. Document why in a one-line comment.

- [ ] **Step 4.5: Record the Phase 1 baseline numbers (and the pre-T1b reference from 4.3 if available) in a comment in `tests/bench_test.mbt`.**

These numbers feed the Phase 2 perf-gate at Task 7.1.

---

## Phase 2: Atomic switchover (ONE task, ONE commit)

**Critical: do not split this phase across multiple commits.** The intermediate state (old named calls AND new hook both firing) corrupts accumulator state because `snapshot_and_clear` is not idempotent — a second invocation overwrites the previous snapshot with an empty buffer. Codex flagged this as a hard correctness issue.

### Task 5: Codex Gate 2 — atomic switchover dry-run ⚠️

- [ ] **Step 5.1: Sketch the full Phase 2 change set on paper.**

Write out:
1. The full `AccumulatorCommitHook` struct + `RecomputeState` substruct
2. The three `impl MemoCommitPhase for AccumulatorCommitHook with ...` blocks
3. The exact diff for `cells/accumulator.mbt` push-path redirects at lines 464, 540, 581
4. The exact diff for `cells/memo.mbt::memo_force_recompute` (deleting three named calls, leaving only the dispatch loops)
5. The exact diff for `cells/internal/kernel/state.mbt` (removing the two `ActiveQuery` fields + `ensure_*` helpers + `None` initializers)
6. The `Runtime::new` change (construct hook once, register in both typed field and dispatch array)

- [ ] **Step 5.2: Submit Gate 2 review to Codex.**

Question: "Review this paper sketch of the atomic switchover. Specifically: is the behavior-preservation rule applied correctly at lines 540 and 581 (silent no-op when frame/entry absent)? Does the nested-recompute case work with HashMap-keyed-by-cell? Is the `in_progress = false` ordering vs. the after_success hook firing safe (specifically, can on_change firing in `recompute_inner` after force_recompute returns observe inconsistent state)?"

Apply Codex's feedback before writing any code.

### Task 6: Atomic switchover commit

- [ ] **Step 6.1: Create `cells/accumulator_commit_hook.mbt`.**

```moonbit
///|
priv struct RecomputeState {
  prev_contributions : Array[@incr_types.AccumulatorId]
  mut touched : @hashset.HashSet[@incr_types.AccumulatorId]?
  mut reads : @hashmap.HashMap[(@incr_types.AccumulatorId, CellId), Revision]?
}

///|
priv struct AccumulatorCommitHook {
  // Per-recompute state, keyed by the cell currently being recomputed.
  // Entry created in `before_recompute`, removed in `after_success`/`after_abort`.
  active : @hashmap.HashMap[CellId, RecomputeState]
}

priv fn AccumulatorCommitHook::new() -> AccumulatorCommitHook {
  { active: @hashmap.HashMap([]) }
}

// Accessors for push paths in cells/accumulator.mbt.
// Silent no-op (returns None) if no entry exists — preserves current
// behavior at cells/accumulator.mbt:537-543 and :578-584.
priv fn AccumulatorCommitHook::for_cell(
  self : AccumulatorCommitHook,
  cell_id : CellId,
) -> RecomputeState? {
  self.active.get(cell_id)
}

priv fn RecomputeState::ensure_touched(
  self : RecomputeState,
) -> @hashset.HashSet[@incr_types.AccumulatorId] {
  match self.touched {
    Some(s) => s
    None => {
      let s = @hashset.HashSet([])
      self.touched = Some(s)
      s
    }
  }
}

priv fn RecomputeState::ensure_reads(
  self : RecomputeState,
) -> @hashmap.HashMap[(@incr_types.AccumulatorId, CellId), Revision] {
  match self.reads {
    Some(m) => m
    None => {
      let m = @hashmap.HashMap([])
      self.reads = Some(m)
      m
    }
  }
}

// before_recompute: snapshot prev contributions, create active entry.
priv impl MemoCommitPhase for AccumulatorCommitHook with before_recompute(
  self, rt, cell_id,
) {
  let prev : Array[@incr_types.AccumulatorId] = match
    rt.accumulator_contributions.get(cell_id) {
    Some(s) => s.to_array()
    None => []
  }
  for slot_id in prev {
    let slot = rt.accumulator_slots[slot_id.id]
    if !slot.disposed { (slot.snapshot_and_clear)(cell_id) }
  }
  self.active.set(cell_id, { prev_contributions: prev, touched: None, reads: None })
}

// after_abort: restore snapshot for prev; clear new-run buffer for touched-not-prev.
priv impl MemoCommitPhase for AccumulatorCommitHook with after_abort(
  self, rt, cell_id,
) {
  let state = self.active.remove(cell_id).unwrap()
  let touched : Array[@incr_types.AccumulatorId] = match state.touched {
    Some(s) => s.to_array()
    None => []
  }
  // Restore prev_contributions
  for slot_id in state.prev_contributions {
    let slot = rt.accumulator_slots[slot_id.id]
    if !slot.disposed { (slot.restore_buffer)(cell_id) }
  }
  // Clear new-run buffer for touched-not-prev
  for slot_id in touched {
    let mut in_prev = false
    for p in state.prev_contributions {
      if p == slot_id { in_prev = true; break }
    }
    if in_prev { continue }
    let slot = rt.accumulator_slots[slot_id.id]
    if !slot.disposed { (slot.clear_new_run_buffer)(cell_id) }
  }
}

// after_success: finalize over prev ∪ touched; commit staged reads + contributions.
// Fires AFTER the cell-level epilogue (changed_at / verified_at set).
priv impl MemoCommitPhase for AccumulatorCommitHook with after_success(
  self, rt, cell_id,
) {
  let state = self.active.remove(cell_id).unwrap()
  let cell = rt.get_memo_data(cell_id)
  // ... (translate the body of `memo_commit_accumulator_phase` from
  //      cells/accumulator.mbt:321 verbatim, replacing query.touched and
  //      query.reads with state.touched and state.reads)
}
```

The `after_success` body is a verbatim port of `memo_commit_accumulator_phase` (`cells/accumulator.mbt:321` and onward), replacing the `query.touched_accumulator_slots` and `query.accumulator_reads` parameters with `state.touched` and `state.reads`. Read the existing function carefully before transcribing; do not paraphrase logic.

- [ ] **Step 6.2: Modify `cells/runtime.mbt::Runtime` struct + `Runtime::new`.**

Add the typed named field:

```moonbit
priv struct Runtime {
  // ... existing fields ...
  priv accumulator_commit_hook : AccumulatorCommitHook
  priv mut commit_hooks : Array[&MemoCommitPhase]
}

pub fn Runtime::new(on_change? : () -> Unit) -> Runtime {
  let id = @kernel.alloc_runtime_id()
  let hook = AccumulatorCommitHook::new()
  let rt : Runtime = {
    core: { ... existing init ..., },
    pull: { ... },
    push: { ... },
    datalog: { ... },
    cell_lifecycle: [],
    accumulator_slots: [],
    accumulator_snapshots: [],
    next_accumulator_id: 0,
    accumulator_contributions: @hashmap.HashMap([]),
    accumulator_commit_hook: hook,
    commit_hooks: [],
  }
  // Register the same hook object in the dispatch array.
  rt.commit_hooks.push(hook)
  rt
}
```

The dispatch array holds the same object as the typed field — different views of one allocation.

- [ ] **Step 6.3: Redirect push paths in `cells/accumulator.mbt`.**

Three sites. Verify line numbers against the current source before editing; the line numbers below are accurate against `main @ 7726cff`.

**Site 1: line 464 inside `Accumulator::push` (must have entry, abort otherwise).**

Replace:
```moonbit
frame.ensure_touched_accumulator_slots().add(self.slot_id)
```

With:
```moonbit
match self.rt.accumulator_commit_hook.for_cell(m_id) {
  Some(state) => state.ensure_touched().add(self.slot_id)
  None => fail("Accumulator::push: no active recompute frame for cell " + m_id.to_string())
}
```

(The `:451` `fail` check already ensures the caller is inside a Memo/HybridMemo compute, so `None` here would indicate an internal invariant violation — fail is appropriate.)

**Site 2: line 540 inside `Memo::accumulated` (silent no-op when absent).**

Replace:
```moonbit
match self.rt.top_active_query() {
  Some(frame) =>
    frame
    .ensure_accumulator_reads()
    .set((acc.slot_id, self.cell_id), current_rev)
  None => ()
}
```

With:
```moonbit
match self.rt.top_active_query() {
  Some(frame) =>
    match self.rt.accumulator_commit_hook.for_cell(frame.cell_id) {
      Some(state) =>
        state.ensure_reads().set((acc.slot_id, self.cell_id), current_rev)
      None => ()  // non-memo frame (push-reactive/effect) — silent no-op
    }
  None => ()  // no frame — silent no-op (top-level call)
}
```

**Site 3: line 581 inside `Memo::accumulated_result` — same shape as Site 2.**

Apply the identical pattern to line 581.

- [ ] **Step 6.4: Delete the three named functions from `cells/accumulator.mbt`.**

Remove:
- `fn memo_snapshot_accumulator_contributions(...)` (line ~250)
- `fn memo_restore_on_abort(...)` (line ~277)
- `fn memo_commit_accumulator_phase(...)` (line ~321)

Confirm no other call sites reference them: `grep -rn "memo_snapshot_accumulator_contributions\|memo_restore_on_abort\|memo_commit_accumulator_phase" cells/ tests/`. Should be zero hits after deletion.

- [ ] **Step 6.5: Delete the three named call sites from `cells/memo.mbt::memo_force_recompute`.**

Remove (the named calls kept around since Phase 1):
- `let prev_contributions = memo_snapshot_accumulator_contributions(...)` (line ~423)
- `memo_restore_on_abort(self, cell_id, prev_contributions)` (line ~430 in catch arm)
- `memo_commit_accumulator_phase(...)` (line ~442)

Remove the `prev_contributions` local variable. The dispatch loops added in Phase 1 now do the work.

- [ ] **Step 6.6: Remove fields from `cells/internal/kernel/state.mbt`.**

In `ActiveQuery`:
- Delete `mut accumulator_reads : @hashmap.HashMap[...] ?` (line ~88)
- Delete `mut touched_accumulator_slots : @hashset.HashSet[...] ?` (line ~92)
- Delete `ensure_accumulator_reads` helper (line ~122)
- Delete `ensure_touched_accumulator_slots` helper (line ~137)
- Delete `accumulator_reads: None,` and `touched_accumulator_slots: None,` initializers (line ~109)

- [ ] **Step 6.7: Migrate whitebox tests that read those fields.**

`grep -rn "accumulator_reads\|touched_accumulator_slots" cells/*_wbtest.mbt`. Migrate any reader to access through `rt.accumulator_commit_hook.for_cell(cell_id)` or delete if redundant. Aim for zero hits in `*_wbtest.mbt` after migration.

- [ ] **Step 6.8: Run verification contract.**

`moon check && moon test && scripts/check-engine-isolation.sh`. All 508+ tests must pass.

If accumulator tests fail, the suspect is either:
1. The verbatim port of `memo_commit_accumulator_phase` body — re-read line by line against the original
2. The push-path redirect at line 540 or 581 — check the no-op preservation
3. The `before_recompute` snapshot timing under nesting

Bisect by reverting one push path or one hook method at a time. Do not proceed until green.

### Task 7: Bench-gate Phase 2 (final perf check)

- [ ] **Step 7.1: Run `moon bench --release` and compare to Phase 1 baseline.**

The `memo: no-accumulator recompute fanout` bench was added in Phase 1 (Task 4.1) precisely to enable this comparison. Compare every row against the numbers recorded in Task 4.4.

Watch:
- `memo: create-dispose cycle` (1.36 µs original baseline)
- `memo: deep chain 100 levels stale` (34.56 µs original baseline)
- `memo: wide fanout 1→50 stale` (21.57 µs original baseline)
- **`memo: no-accumulator recompute fanout`** — compare against Phase 1 number (Task 4.4)
- `push: propagation 100 live reactives` (17.39 µs original baseline — should be UNAFFECTED)

All must be within ±5% of the Phase 1 numbers. If the no-accumulator bench regresses, the suspect is HashMap insert/remove on every recompute even when no accumulator is touched. Mitigations:
- Skip `active.set(cell_id, ...)` if no accumulators are registered yet (`rt.accumulator_slots.is_empty()`)
- Use a thinner per-cell state struct (e.g., bitfield instead of Option fields)
- Document an acceptable regression IF the absolute cost is still small (negotiate with Codex review)

- [ ] **Step 7.2: If any row regresses >5%, stop and analyze.**

If shape (2) is non-recoverable on perf grounds, the fallback is shape (1): keep `accumulator_reads` and `touched_accumulator_slots` on `ActiveQuery`, have the hook read `top_active_query()` for abort and the just-popped query (stashed at hook level between pop_tracking_full and after_success) for success. Most of Tasks 6.1–6.5 still apply; Task 6.6 (removing ActiveQuery fields) reverses. Update the ADR before re-planning.

---

## Phase 3: Tests, docs, finalize

### Task 8: Add invariant tests

- [ ] **Step 8.1: Create `cells/accumulator_commit_hook_wbtest.mbt` with three tests.**

**Test A — Dispatch order (forward on both success and abort):**

Register a sentinel hook *after* the accumulator at `Runtime::new` (via a private test helper). Run a memo recompute that succeeds. Verify accumulator runs before sentinel by checking observable order of writes. Then run a memo recompute that aborts. Verify accumulator's after_abort runs before sentinel's after_abort.

**Test B — Non-memo-frame preservation:**

Construct a push-reactive whose compute calls `Memo::accumulated(some_memo, some_acc)`. Verify no crash, no aborted invariant, and that the recomputing reactive's pop does not leave any accumulator state behind. Same test for `Memo::accumulated_result`.

**Test C — Nested recompute correctness:**

Construct memos M1 and M2 where M1's compute reads M2 (via `get`). Set a signal to invalidate both. Read M1, which triggers M2's recompute mid-M1's-recompute. Have M2 abort. Verify:
- M2's `active[m2_cell]` entry is removed after abort
- M1's `active[m1_cell]` entry is still present (M1 has not finished yet)
- M1's recompute then aborts (because M2's error propagates) — verify M1's entry is then also removed

### Task 9: Documentation + cross-references

- [ ] **Step 9.1: Update `docs/design/internals.md`.**

In the Accumulator section, replace "called by name from memo.mbt" with a brief explanation of the `MemoCommitPhase` trait + `commit_hooks` dispatch + the post-epilogue timing. Document that this is the extension point future cross-cutting concerns register against, and link to the T1b ADR.

Do not include implementation details (struct fields, file paths) per the project's docs convention.

- [ ] **Step 9.2: Update `CLAUDE.md` Package Map.**

Add `cells/memo_commit_phase.mbt` (trait, lives in `cells/` not kernel) and `cells/accumulator_commit_hook.mbt` (first impl). One sentence each.

- [ ] **Step 9.3: Codex Gate 3 — post-implementation review ⚠️**

Submit the actual merged Phase 2 commit to Codex with the question: "Review the implementation against the amended ADR. Specifically: (1) is the verbatim port of `memo_commit_accumulator_phase` correct? (2) does the silent-no-op preservation at lines 540/581 match current behavior? (3) is the `Runtime::new` two-step init (struct literal then push) actually safe — no callback fires between the literal and the push? (4) any sequencing concerns around `after_success` firing after the epilogue, vs. `recompute_inner`'s `on_change` firing after force_recompute returns?"

Apply Codex's feedback. Open a follow-up commit if necessary.

- [ ] **Step 9.4: Mark plan complete.**

Add a `**Status:** Complete` header. Add a `**Decision record:** [T1b ADR](../decisions/2026-05-17-t1b-memo-commit-phase.md)` line. Reference the visualization-tap follow-up ADR.

- [ ] **Step 9.5: `git mv docs/plans/2026-05-17-t1b-implementation.md docs/archive/plans/2026-05-17-t1b-implementation.md`.**

Update `docs/README.md` index entry to point to the archive path.

- [ ] **Step 9.6: Run verification contract one last time + final commit.**

---

## Final verification (before PR open)

| Check | Requirement |
|---|---|
| `moon check` | zero errors |
| `moon test` | 508+ passed (existing) + 3 new wbtests, 0 failed |
| `moon info && moon fmt` | no public `.mbti` drift |
| `scripts/check-engine-isolation.sh` | green |
| `moon bench --release` | all tracked rows + new memo-no-accumulator bench within ±5% of baseline |
| Codex review (Gates 1, 2, 3) | all three completed; feedback incorporated |
| `grep -rn "memo_snapshot_accumulator_contributions\|memo_restore_on_abort\|memo_commit_accumulator_phase" cells/ types/ tests/` | zero hits |
| `grep -rn "accumulator_reads\|touched_accumulator_slots" cells/internal/kernel/state.mbt` | zero hits |
| `grep -rn "ensure_accumulator_reads\|ensure_touched_accumulator_slots" cells/` | zero hits |
| `git diff --stat` | only files in the file map above; no unintended drift |

## Rollback contract

This refactor is a single PR with the atomic switchover concentrated in one commit (Phase 2). If post-merge defects surface (regression in accumulator behavior, perf cliff, or invariant violation):

- **Revert is one PR.** Restore the three named functions in `accumulator.mbt`, restore the two `ActiveQuery` fields + helpers, restore the three call sites in `memo.mbt`, delete the new files.
- **No data migration** — accumulator state is in-process, no on-disk serialization affected.
- **No downstream consumer impact** — public API unchanged.

## What this plan deliberately defers

- The `MemoEvent` enum + `Runtime::on_memo_event` public API (separate plan, separate PR, depends on this plan landing). Per [Memo Event Observation ADR](../decisions/2026-05-17-memo-event-observation.md).
- A second built-in hook impl (visualization event tap). Designed in the follow-up ADR; implemented in its own plan.
- Pull-mode-only scope. No push-reactive, fixpoint, batch-commit, or signal-change hook surfaces are added.
- Public `pub` trait visibility. Stays `priv`.
- Snapshot/restore API surface for time-travel debugging. Deferred per ADR until CRDT / event-graph-walker integration.

## Codex review log (this PR's gates)

| Gate | Step | Status |
|---|---|---|
| Gate 1 | Task 1.3 — trait shape + file placement + Runtime field | pending |
| Gate 2 | Task 5.2 — atomic switchover paper sketch | pending |
| Gate 3 | Task 9.3 — merged Phase 2 commit | pending |

Record Codex's response + any follow-up actions in this section as each gate completes.

## Sub-skill checklist (for the agent executing this plan)

- [ ] Read the **amended** T1b ADR end-to-end before starting Task 1.
- [ ] Confirm worktree is in `.worktrees/t1b-memo-commit-phase` and branch is `refactor/t1b-memo-commit-phase`.
- [ ] Run the verification contract after **every** task — not just at gates.
- [ ] Do not skip Codex review at Gate 1 (Task 1.3), Gate 2 (Task 5.2), or Gate 3 (Task 9.3).
- [ ] Phase 2 is **one commit**. Do not stage the switchover across multiple commits — the intermediate state corrupts accumulator state because `snapshot_and_clear` is not idempotent (Codex finding, see ADR amendment).
- [ ] If the bench gate fails at Task 7.1 (compared to Phase 1 baseline), do not work around it — invoke the shape-(1) fallback documented in Task 7.2 or stop and report.
- [ ] If unexpected `.mbti` drift appears, stop and audit. The plan expects zero public API change.
- [ ] When complete, run `superpowers:verification-before-completion`'s discipline: every claim of completeness must be backed by command output, not assertion.
