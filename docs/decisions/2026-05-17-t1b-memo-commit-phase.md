# ADR: T1b (`MemoCommitPhase`) — Scoped to Event-Stream Observation

**Date:** 2026-05-17 (amended same-day after Codex pre-implementation review)
**Status:** Accepted — refactor scope defined; implementation gated on a written plan
**Anchors:** [Async-at-the-edges](2026-05-17-async-at-the-edges.md), [T3 deferred](2026-05-17-t3-runtime-registry-gated.md), [Accumulator API](2026-04-20-accumulator-api.md), [2026-04-20 architecture assessment](../design/specs/2026-04-20-architecture-assessment.md) (AP1, §4 T1b)

**Amendments (2026-05-17, post-Codex):**
- §"Trait shape": trait lives in `cells/`, not `cells/internal/kernel/`. The MoonBit engine-isolation rule forbids back-edges from `cells/internal/kernel/` into `cells/`, and a trait that takes `rt : Runtime` cannot live in kernel. Mirrors the `CellLifecycle` precedent.
- §"Dispatch": `commit_hooks` field on `Runtime`, not `RuntimeCore`. Same reason.
- §"Hook timing": `after_success` fires **after the cell-level epilogue** (after `changed_at` / `verified_at` / `has_been_computed` / `in_progress = false`). Backdating is detectable via `cell.meta.changed_at < cell.verified_at`. Accumulator's commit work is order-independent w.r.t. the epilogue (verified by reading `cells/memo.mbt:451–477` and `cells/accumulator.mbt::memo_commit_accumulator_phase`).
- §"Dispatch order": forward order on **both** success and abort. Explicit, contracted.
- §"Accumulator refactor": dropped the `commit_hooks[0]` downcast pattern. Use a typed named field `priv accumulator_commit_hook : AccumulatorCommitHook` plus register the *same object* in `commit_hooks`. Drops the brittle invariant.

## Context

The 2026-04-20 architecture assessment identified **AP1** — the accumulator feature's three commit-path hooks (`memo_snapshot_accumulator_contributions`, `memo_restore_on_abort`, `memo_commit_accumulator_phase`) are called by literal name from `cells/memo.mbt:423-449`. With one implementor, naming the hooks is fine. The gate for the proposed **T1b** trait abstraction was a *second* cross-cutting concern with the same hook shape.

That driver has been named: **live event-stream observation for visualization** of the dependency graph. A visualization tool wants to render commit-phase events — which memos entered recompute, which completed, which aborted, with what timing — and the natural hook shape is identical to the accumulator's:

| Hook | Accumulator use | Visualization use |
|---|---|---|
| `before_recompute(cell_id)` | Snapshot `accumulator_contributions[cell_id]` | Start timer; emit "entering compute" event |
| `after_success(cell_id)` | Commit new pushes (collected during recompute via `accumulator_reads` / `touched_accumulator_slots`); discard snapshot | Emit "completed" event with elapsed time + backdated flag |
| `after_abort(cell_id)` | Restore snapshot, drop in-progress pushes | Emit "aborted" event with elapsed time |

Two implementors with the same hook contract, distinct abort semantics, and no shared state. This is the shape the assessment named as the gate condition.

The trade now pays: refactor the three named calls in `memo.mbt` into trait dispatch over `Array[&MemoCommitPhase]`. The accumulator becomes the first registered implementor; the visualization tap becomes a second implementor in a follow-up PR.

## What this ADR is and is not

**This ADR is:**
- A decision-record commissioning T1b's design
- A specification of trait shape, dispatch contract, scope of refactor, and verification gates
- The retirement of the 2026-04-20 gate (driver is now named)

**This ADR is not:**
- An implementation plan (that goes in `docs/plans/` when the PR is opened)
- A spec for the visualization tap impl (separate follow-up after T1b lands)
- A commitment to publish a `pub` extension point (trait stays `priv`; see §"Visibility")
- A spec for snapshot/restore / time-travel debugging — the user deferred those pending CRDT (event-graph-walker) integration; tracked as future work, not T1b's scope

## Current state to be refactored

Three named-call sites in `cells/memo.mbt::memo_force_recompute` (verified against `main @ 7726cff`):

```moonbit
// cells/memo.mbt:423 — BEFORE_CLOSURE
let prev_contributions = memo_snapshot_accumulator_contributions(self, cell_id)

// cells/memo.mbt:430 — AFTER_ABORT (inside catch arm)
memo_restore_on_abort(self, cell_id, prev_contributions)

// cells/memo.mbt:442-449 — AFTER_SUCCESS
memo_commit_accumulator_phase(
  self, cell, cell_id, prev_contributions,
  query.touched_accumulator_slots,
  query.accumulator_reads,
)
```

The success path additionally consumes two accumulator-specific fields from `ActiveQuery` (`touched_accumulator_slots`, `accumulator_reads`). These are collected during recompute via `record_dep` and accumulator-push paths; they have no meaning for non-accumulator concerns.

## Decision

### Trait shape

```moonbit
// cells/memo_commit_phase.mbt (new file — NOT in cells/internal/kernel/)
priv trait MemoCommitPhase {
  before_recompute(Self, Runtime, CellId) -> Unit
  after_success(Self, Runtime, CellId) -> Unit
  after_abort(Self, Runtime, CellId) -> Unit
}
```

Three methods, no `Snapshot` associated type, no return values. Each implementor owns its own per-cell state internally (the way the accumulator already stashes via `accumulator_contributions`). This avoids two known pain points:

- **MoonBit traits do not support associated types.** A generic `Snapshot` would require type erasure via an opaque trait object; per-implementor internal state is simpler.
- **Different implementors want different snapshot shapes.** Accumulator wants `HashSet[AccumulatorId]`; a visualization tap wants `(Int64, String?)`. Forcing a single shape across the trait would compromise both.

The trade-off: implementors carry more state. Worth it because the alternative is type erasure on the hot commit path.

**Trait file placement is `cells/`, not `cells/internal/kernel/`.** Because the trait methods take `rt : Runtime`, and `Runtime` lives in `cells/`, a kernel-resident trait would force a back-edge from `cells/internal/kernel/` into `cells/`, which `scripts/check-engine-isolation.sh` forbids (invariant #4). This mirrors the `CellLifecycle` precedent: it stays on `Runtime` for exactly the same reason (`cells/runtime.mbt:30`).

### Dispatch

`Runtime` gains one new field, **on `Runtime` itself, not `RuntimeCore`** — same reasoning as the trait file placement:

```moonbit
// On Runtime (not RuntimeCore):
priv mut commit_hooks : Array[&MemoCommitPhase]
```

`memo_force_recompute` becomes (timing precise — see §"Hook timing" below):

```moonbit
// 1. BEFORE — before tracking is pushed:
for hook in self.commit_hooks { hook.before_recompute(self, cell_id) }
let old_deps = cell.dependencies
@kernel.push_tracking(self.core, cell_id)

let new_value = compute_fn() catch {
  e => {
    // 2. ABORT — inside catch arm, before pop_tracking_full:
    for hook in self.commit_hooks { hook.after_abort(self, cell_id) }
    let _ = @kernel.pop_tracking_full(self.core)
    cell.in_progress = false
    raise e
  }
}

let query = @kernel.pop_tracking_full(self.core)
// ... existing cell-level epilogue:
//   diff_and_update_subscribers, cell.dependencies = new_deps,
//   compute_durability, backdate check + changed_at update,
//   verified_at, has_been_computed, in_progress = false ...

// 3. SUCCESS — AFTER the cell-level epilogue:
for hook in self.commit_hooks { hook.after_success(self, cell_id) }

Ok(new_value)
```

**Dispatch order is forward on both success and abort.** Explicit contract. Accumulator (registered first) runs before later hooks on both paths. A later visualization hook will see post-accumulator state regardless of which branch fired.

### Hook contract — implementors must not call user code or graph-read APIs inline

`MemoCommitPhase` is internal scaffolding. Implementors mutate their own per-cell state and read runtime fields. They **must not**:

- Call user-supplied callbacks inline (e.g., `Signal::on_change` / `Memo::on_change` closures or registered listeners)
- Call public graph-read APIs (`Memo::get`, `Signal::get`, `Memo::accumulated`, etc.)
- Mutate cell metadata that affects `recompute_inner`'s post-`force_recompute` decisions (specifically, `cell.meta.changed_at` must already be in its final post-epilogue state)

Three concrete reasons:

1. **Typed value not yet written.** The hook fires inside `memo_force_recompute`, but the typed wrapper at `Memo::force_recompute` (and `HybridMemo::force_recompute`) writes `self.value = Some(new_value)` *after* this returns. A user callback that synchronously reads the memo would see the stale (or `None`) typed cache.
2. **Nested-recompute dep pollution.** After `pop_tracking_full` for the inner recompute, an outer frame may still be live. `record_dep` records into the top frame unconditionally (`cells/internal/kernel/tracking.mbt:47`). A user callback that reads any memo from inside the hook would land its reads on the outer frame, corrupting the outer's dependency set.
3. **`recompute_inner` decisions depend on epilogue state.** `recompute_inner` computes `changed = cell.meta.changed_at != old_changed_at` *after* `force_recompute` returns (`cells/memo.mbt:352-358`) and decides whether to fire `on_change`. A hook mutating `changed_at` would flip that decision.

Implementors that need to surface events to user code must use **buffer-and-flush**: append to an internal queue inside the hook, and arrange for the queue to drain at a safe point (when `tracking_stack.is_empty()` and after the typed value is written). The visualization event tap follow-up ADR specifies the drain protocol; this contract pins the constraint at the trait level.

The accumulator hook (this ADR's only implementor) satisfies the contract: it mutates only its own slot state and runtime fields, calls no user code.

### Hook timing — `after_success` after the cell-level epilogue

The earlier draft placed `after_success` *before* the cell-level epilogue (where today's `memo_commit_accumulator_phase` runs). Codex pre-implementation review flagged a downstream problem: the visualization follow-up ADR specifies `Completed(...backdated~ : Bool)`, and `backdated` cannot be detected until after `cell.meta.changed_at` is conditionally updated by the epilogue.

Resolution: fire `after_success` after the epilogue. Backdating is then detectable from cell state alone — `cell.meta.changed_at < cell.verified_at` ⟺ recompute happened but did not advance changed_at ⟺ backdated.

Accumulator correctness under this move was verified by reading `cells/accumulator.mbt::memo_commit_accumulator_phase`: it reads `rt.core.revision.current_revision` (runtime-wide, not cell-specific), writes to per-memo accumulator buffers and slot `push_revised_at`, and does **not** depend on epilogue values (`cell.dependencies`, `cell.meta.changed_at`, `cell.verified_at`, `has_been_computed`). The original placement before-epilogue was happenstance, not a load-bearing ordering invariant.

`after_abort` keeps its place in the catch arm before pop. Today's `memo_restore_on_abort` reads `top_active_query()` for `touched_accumulator_slots`; under shape (2) below, the hook reads its own per-cell state instead, so this timing also becomes order-independent — but kept here to minimize diff against the existing code structure.

### Visibility — `priv`, not `pub`

The trait stays `priv` for now. Public API is added only when a concrete public surface is requested by a driver. The reasoning:

- **`pub` traits are commitments.** Locking in the trait shape with `pub` before the visualization tap has been implemented is the speculative-abstraction failure mode the 2026-04-20 ADR warned against. We have *one* shipped impl + *one* designed impl; that's enough to justify the refactor, not enough to publish the trait.
- **Driver-facing observability gets a different API.** When visualization implementation lands, it ships as `Runtime::on_memo_event(f : (MemoEvent) -> Unit) -> Unit` — a public callback registration backed by an in-tree `EventBroadcastPhaseHook` implementor. Drivers see callbacks, not traits.
- **Future cross-cutting concerns** (persistent caching, delta observers if they ever arrive) can be additional in-tree impls without changing the public API surface.

### Accumulator refactor (in this ADR's scope)

The existing `memo_snapshot_accumulator_contributions` / `memo_restore_on_abort` / `memo_commit_accumulator_phase` get repackaged into an `AccumulatorCommitHook` struct implementing `MemoCommitPhase`. The hook closes over the runtime's accumulator state.

`Runtime` carries the hook by **typed named field**, with the same object also registered into the dispatch array:

```moonbit
priv struct Runtime {
  ...
  priv accumulator_commit_hook : AccumulatorCommitHook
  priv mut commit_hooks : Array[&MemoCommitPhase]
}
```

Push paths in `cells/accumulator.mbt` reach the hook through `self.rt.accumulator_commit_hook`, not via array-index downcast. The dispatch array exists for trait-polymorphic iteration in `memo_force_recompute`; the named field exists for typed access. (An earlier draft used `commit_hooks[0]` plus a `priv fn Runtime::accumulator_hook(self)` downcast accessor. That pattern is a brittle hidden invariant — if any future code inserts a hook ahead of accumulator, the invariant silently breaks. The typed field eliminates the question.)

**Decision: shape (2) is the default.** `touched_accumulator_slots` and `accumulator_reads` move **off** `ActiveQuery` and **onto** the `AccumulatorCommitHook`'s per-cell state. Rationale:

- The two fields exist on `ActiveQuery` today only because the accumulator's named-call commit phase needed them on the just-popped query. With trait dispatch and per-cell hook state, the kernel state struct stays clean of accumulator-specific concerns.
- The lazy-allocation perf work (PR #50, 2026-05-16) on push-reactive frames is unaffected: push-reactive recompute does not trigger memo commit hooks, so push-reactive frames never touch the new HashMap.

**Behavior preservation rule (load-bearing — preserves current semantics):** when redirecting the three push sites, the lookup-by-recomputing-cell must preserve current "no frame → no-op" tolerance at the two tracked variants:

- `cells/accumulator.mbt:464` (`Accumulator::push`) — requires a memo recompute frame. The existing function aborts at `:451` if the current frame is not Memo/HybridMemo. Redirect: look up `accumulator_commit_hook.active[cell_id]`; if absent (shouldn't happen given the line-451 check), abort with the same message.
- `cells/accumulator.mbt:540` (`Memo::accumulated`) — has `match top_active_query() { Some(frame) => ...; None => () }` at `:542`. Today this silently no-ops when called outside any tracking frame. Under shape (2): look up `accumulator_commit_hook.active[cell_id_of_top_frame]`; if frame absent OR entry absent, **silently no-op**. Preserves current behavior.
- `cells/accumulator.mbt:581` (`Memo::accumulated_result`) — same shape as `accumulated`. Same redirect rule.

`Memo::accumulated_peek` at `:474–499` is untracked and never calls `ensure_accumulator_reads` — **not a redirect site**. Earlier plan drafts misidentified this. Verified by reading the function body.

The non-memo-frame case is real: `Memo::accumulated` and `accumulated_result` can be called from inside a push-reactive or effect compute frame. Today's lazy-allocation makes that a harmless no-op (the staged reads are allocated but discarded on `pop_tracking` for non-memo frames). Under shape (2), the equivalent is "no hook entry for the recomputing cell → no write." Same observable behavior.

### Visualization tap (deferred to a separate PR)

The visualization tap is the *design witness* for T1b — it informed the trait shape. It is **not** implemented in T1b's PR. The visualization tap PR will:

1. Add `pub enum MemoEvent { EnteringCompute(CellId) | Completed(CellId, elapsed_ns : Int64, backdated : Bool) | Aborted(CellId, elapsed_ns : Int64, error : String) }`.
2. Add `pub fn Runtime::on_memo_event(self : Runtime, f : (MemoEvent) -> Unit) -> Unit`.
3. Add `priv struct EventBroadcastPhaseHook { callbacks : Array[(MemoEvent) -> Unit], timers : HashMap[CellId, Int64] }` implementing `MemoCommitPhase`.
4. Wire registration through `Runtime::on_memo_event`.

This is a separate ADR + plan when commissioned. The T1b refactor alone justifies its own PR by giving the accumulator a principled extension point.

## What this gates / unblocks

| Concern | Status after T1b |
|---|---|
| Accumulator extension-point principle | Resolved — AP1 closed |
| Live commit-phase visualization | Unblocked — implementor + public API land in follow-up PR |
| Snapshot/restore (point-in-time state capture) | **Still gated.** Read-only API expansion; not T1b's shape. Reopen when needed |
| Time-travel debugging with CRDT integration | **Still gated.** State restoration is a much larger ADR; pending event-graph-walker integration |
| Persistent caching | **Still gated.** Roadmap Phase 5. T1b's hooks are a candidate substrate but the caching ADR has not been written |
| Delta observers (Family A research) | **Still gated.** Driver discovery owned by canopy |

## Migration plan (when commissioned)

Single PR, three phases. **Three** Codex review gates (pre-trait-shape, pre-atomic-switchover, post-switchover).

The earlier draft of this section staged the work as "trait skeleton → accumulator first impl → delete old code" across three task boundaries. Codex review identified that the intermediate state (old named calls still firing alongside new dispatch loops) corrupts accumulator state because `snapshot_and_clear` is not idempotent: a second call overwrites the just-stored snapshot with an empty buffer. The phases below collapse the corrupting window: the dispatch loops are added empty (Phase 1), then the switchover from named-calls to hook-dispatched is atomic in a single Phase 2 task.

### Phase 1 — Trait + dispatch loops, hook *not yet registered* (no behavior change)

- Add `cells/memo_commit_phase.mbt` with the `priv trait`.
- Add `priv mut commit_hooks : Array[&MemoCommitPhase]` field on `Runtime`. Initialize to `[]`.
- Modify `memo_force_recompute` to call the three dispatch loops at the timing points in §"Dispatch":
  - `before_recompute` loop before `push_tracking`
  - `after_abort` loop inside the catch arm before `pop_tracking_full`
  - `after_success` loop **after** the cell-level epilogue
- **Keep all three existing named calls in `memo_force_recompute`.** The dispatch list is empty, so the loops are no-ops. Behavior is byte-identical to pre-T1b.
- **Add a `memo: no-accumulator recompute fanout` microbench** to `tests/bench_test.mbt` — pure-pull workload that recomputes memos without touching accumulators, the path that pays hook dispatch + HashMap insert/remove for no benefit. Capturing this number while in Phase 1 establishes a pre-switchover baseline against which Phase 2 is measured.

Verification: all 508+ tests stay green. Bench gate ±5% on commit-path benches (overhead expected to be sub-1ns; if measurable, add `commit_hooks.is_empty()` fast-path).

### Phase 2 — Atomic switchover (one task, one commit)

Single atomic change. Do **not** stage this across multiple commits — the corrupting double-snapshot intermediate state is the failure mode Codex flagged.

In one commit:
1. Add `cells/accumulator_commit_hook.mbt` with `priv struct AccumulatorCommitHook` + impl. Use the per-cell `HashMap[CellId, RecomputeState]` (shape (2)) with the behavior-preservation rules from §"Accumulator refactor".
2. Add `priv accumulator_commit_hook : AccumulatorCommitHook` field to `Runtime`.
3. In `Runtime::new`, construct the hook once and use the same reference in both the typed field and the `commit_hooks.push(...)` registration.
4. Redirect the three push sites in `cells/accumulator.mbt` (lines 464, 540, 581 in the current source — verify against `main` before editing) to write through `self.rt.accumulator_commit_hook.active[recomputing_cell_id]` instead of `frame.ensure_*`. Preserve the "frame absent → no-op" behavior at lines 540 and 581.
5. Delete the three named call sites in `memo_force_recompute` (the locations marked BEFORE/ON_ABORT/AFTER_SUCCESS in §"Dispatch").
6. Delete the three free functions in `cells/accumulator.mbt` (`memo_snapshot_accumulator_contributions`, `memo_restore_on_abort`, `memo_commit_accumulator_phase`).
7. Remove `accumulator_reads` and `touched_accumulator_slots` fields from `ActiveQuery` in `cells/internal/kernel/state.mbt`, along with the `ensure_*` helpers and the `None` initializers.
8. Migrate any whitebox test that directly inspects those `ActiveQuery` fields.

Verification: all 508+ tests stay green, including 41 accumulator tests + the lambda type-checker incrementality test (loom PR #94 — retroactively, by building loom against the new incr). Specifically, the abort-preservation invariant (`1715981`) must hold — `after_abort` must restore exactly what `before_recompute` snapshotted.

### Phase 3 — Documentation + verification

- Update `docs/design/internals.md` "Accumulator" section: hooks are trait-dispatched; list `MemoCommitPhase` as the extension point. Document that it is an internal extension point, not a public API.
- Add a paragraph explaining how a future hook (e.g., visualization) would be registered.
- Update `CLAUDE.md` Package Map to include `cells/memo_commit_phase.mbt` + `cells/accumulator_commit_hook.mbt`.
- Bench gate (final): commit-path benches within ±5% of the **Phase 1 baseline** (per §"Migration plan" Phase 1, the `memo: no-accumulator recompute fanout` bench was added there to establish a pre-switchover number against which Phase 2 is measured).

## Verification

| Check | Requirement |
|---|---|
| `moon test` | 508+ tests, all green (including 41 accumulator + loom-driver coverage) |
| `scripts/check-engine-isolation.sh` | Green — new files live in `cells/`, no engine-boundary violation |
| `moon bench --release` on `tests/bench_test.mbt` | Commit-path benches within ±5% of pre-T1b baseline. **Including a new memo-no-accumulator bench** added in Phase 3. If overhead is measurable, add `commit_hooks.is_empty()` fast-path |
| `moon info && moon fmt` | No public `.mbti` diff (trait is `priv`; no API change) |
| Codex pre-trait-shape review (Gate 1) | Trait location + signatures + Runtime field placement |
| Codex pre-atomic-switchover review (Gate 2) | Hook struct + impl + push-path redirects, paper review before any code lands |
| Codex post-implementation review (Gate 3) | The merged Phase 2 commit reviewed against the rewritten `memo_force_recompute` + accumulator hook + push redirects |
| Hook ordering test | Whitebox test verifying forward-insertion-order dispatch on both success and abort (matters when a second impl lands) |
| Abort-preservation test | Existing accumulator test `1715981` covers this; must remain green |
| Non-memo-frame test (new) | Whitebox: `Memo::accumulated` and `accumulated_result` called from inside a push-reactive or effect compute frame stay no-op. Preserves behavior currently relied upon (per `cells/accumulator.mbt:537–543` and `:578–584`) |
| Nested-recompute test (new) | Whitebox: outer memo M1 recompute reads inner memo M2 → inner recompute pushes accumulator state → inner aborts → outer continues. Verify M1's hook entry is intact and M2's hook entry is gone |

## Risks

| Risk | Mitigation |
|---|---|
| Dispatch overhead on commit hot path | Bench gate; add zero-implementor fast-path if measurable |
| Trait shape wrong for visualization | Visualization is design witness, not shipped — if its needs differ when actually implemented, reopen this ADR before adding the second impl |
| `ActiveQuery` accumulator fields refactor breaks tracking semantics | Codex review on the relocation; whitebox tests for both shapes |
| Lock-in of `priv` trait shape | Mitigated by `priv` visibility — refactoring the trait later is internal-only, no downstream consumers |

## Trade-offs accepted

- **Refactor with one shipped + one designed implementor.** Slightly relaxes the 2026-04-20 "two real implementors" gate. The relaxation is justified by the designed impl being concretely specified (event types, public API shape, internal hook impl) and by the cost of the refactor being small. If visualization implementation later reveals the trait shape was wrong, the `priv` visibility makes correction internal-only.
- **Per-implementor state instead of associated-type `Snapshot`.** Trades simpler trait shape for more boilerplate inside each impl. The accumulator already manages its snapshot state internally, so net code change is small.
- **Public observability API deferred.** Drivers can't tap into events until the follow-up visualization PR ships. Acceptable because the accumulator refactor alone is the load-bearing piece — the trait exists either way, the public API is just timing.
- **Snapshot/restore / time-travel deferred.** Explicitly. Per the user, that's a CRDT-integration concern via event-graph-walker, not a T1b concern.

## Scope

**In scope of T1b's PR:**
- New file `cells/memo_commit_phase.mbt` with the `priv trait` (lives in `cells/`, **not** `cells/internal/kernel/` — see §"Trait shape")
- New file `cells/accumulator_commit_hook.mbt` with `AccumulatorCommitHook` + impl
- `commit_hooks : Array[&MemoCommitPhase]` field on `Runtime` (not `RuntimeCore`)
- `accumulator_commit_hook : AccumulatorCommitHook` typed field on `Runtime`
- Refactor `memo_force_recompute` to dispatch via trait (with `after_success` placed AFTER the cell-level epilogue per §"Hook timing")
- Repackage the three named accumulator functions into `AccumulatorCommitHook` (shape (2): per-cell HashMap state, fields removed from `ActiveQuery`)
- Doc updates in `docs/design/internals.md`
- Zero-implementor fast-path **if** bench gate triggers it
- New memo-no-accumulator microbenchmark, landed in Phase 1 to establish a pre-switchover baseline

**Out of scope of T1b's PR (deferred to follow-up ADRs/plans):**
- `MemoEvent` enum and `Runtime::on_memo_event` public API
- `EventBroadcastPhaseHook` impl
- Visualization tool itself (canopy-side concern)
- Snapshot API expansion (read-only state walk)
- State restoration API (replay)
- CRDT / event-graph-walker integration
- Persistent caching design
- Hook events for non-pull-mode cells (push propagation, fixpoint, batch commit)
- `pub` versions of the trait

## What this ADR retires

- The 2026-04-20 architecture assessment's gate "Build [T1b] only when a second concern is specified." Driver is now specified (visualization event tap), and the trait shape is informed by both implementors.
- The named-call coupling between `memo_force_recompute` and the accumulator's three helpers. After T1b, the accumulator is a registered implementor like any other.
- The implicit assumption that the next cross-cutting commit-path concern would need its own bespoke wiring. After T1b, it registers an impl.

## What this ADR explicitly does not retire

- The driver-gate principle. T1b is being commissioned *because* a second driver was named, not despite the gate. Future hook extensions (commit events on push cells, fixpoint events, batch events) still need their own drivers.
- The "no public extension API without driver request" principle. The trait stays `priv`. A public observability API ships only when the visualization tap implementation is ready.
- The T3 gate. T1b and T3 are independent; commissioning T1b does not lift T3's gate.
