# R1 Stage 0 — Codex Design Review

**Date:** 2026-04-24
**Reviewer:** Codex (gpt-5.2-codex via mcp), read-only sandbox
**Target:** [R1 plan v2](2026-04-21-r1-engine-package-split.md) + [audit findings](2026-04-21-r1-stage0-audits.md)

## Verdict

**READY WITH CAVEATS.** Four concrete corrections needed before Stage 1; none are structural rejections of the plan's shape. One Stage 4 finding is a hard blocker on the plan text ("kernel owns dispose coordinator") and requires a text change, though not a redesign.

## 1. Staging order / dependency safety

Stage 3 order is mostly right through 3f, and Stage 4 batch-after-propagate is correct (`commit_batch` calls `propagate_changes` and `fire_on_change` in `cells/batch.mbt:149`; `gc_sweep` calls `dispose_cell`, so dispose-before-gc in Stage 4 holds — `cells/runtime.mbt:862`).

**Two caveats:**

- **3c tracking is not actually leaf-first.** If `3c` includes `finish_tracking`, it calls `diff_and_update_subscribers` at `cells/tracking.mbt:154`, which the plan schedules for `3d`. Either exclude `finish_tracking` from 3c, or swap the order so `subscriber_diff` moves in 3c and tracking moves in 3d.
- **3g fixpoint is not self-contained.** `fixpoint()` ends by calling `publish_cell_changes` at `cells/datalog_fixpoint.mbt:107`, which stays in Runtime until Stage 4 per the plan (`cells/runtime.mbt:665`). Either keep a thin `Runtime::fixpoint` wrapper until Stage 4, or hoist `propagate_changes` + `publish_cell_changes` into Stage 3 ahead of 3g.

## 2. SlotSnapshot trait — shape is wrong

**Boundary is right in principle, trait shape is not.** Verify does not read a slot-wide revision; it reads per-memo state: `slot.push_revised_at_for(target_id)` at `cells/verify.mbt:86`, backed by per-memo HashMap state in `cells/accumulator.mbt:16` and `:97`.

**Minimal correct trait:**

```moonbit
pub trait SlotSnapshot {
  disposed(Self) -> Bool
  push_revised_at_for(Self, CellId) -> Revision  // was: push_revised_at()
}
```

**On R4 (trait-object dispatch cost):** over-cautious. The verify path already does HashMap lookup + sometimes recursive `pull_verify` at `cells/verify.mbt:97`; one vtable call is not going to dominate. The bigger unproven risk is whether `Runtime::slot_snapshots()` can expose `Array[&SlotSnapshot]` without allocating a new array per call. Plan assumes zero-copy without stating so.

## 3. Blind spots / hidden couplings

**Stage 4 dispose coordinator is blocked as written.** `CellLifecycle` lives in top-level `cells/cell_ops.mbt:52`, not `internal/shared/`, and its `dispose_cell` method takes a full `Runtime`. Current impls use runtime helpers and runtime-owned fields directly (`cells/pull_memo_lifecycle.mbt:8`, `cells/push_lifecycle.mbt:5`, `cells/datalog_lifecycle.mbt:8`). **`kernel/dispose.mbt` cannot own the full coordinator** as Stage 4 currently claims — either dispose stays partly in `cells/runtime.mbt`, or the `CellLifecycle` signature must change to take `RuntimeCore` + state refs instead of `Runtime`. The plan needs to pick one explicitly.

**Phase state machine move is unnamed.** The plan says kernel owns the phase state machine, but the Stage 2 move list never names `enter_phase` / `leave_phase`, even though moved algorithms rely on them in `cells/runtime.mbt:241`, `cells/push_propagate.mbt:129`, `cells/datalog_fixpoint.mbt:30`. Add to Stage 2's state move list explicitly.

**"Kernel never mentions a concrete cell kind" is too strong.** Dispatch, verify, and push-propagate all branch on `CellRef` variants in `cells/runtime.mbt:393`, `cells/verify.mbt:121`, `cells/push_propagate.mbt:153`. The real enforceable boundary is *"kernel never depends on `cells/`-only state like `SlotMeta` or handle-specific logic"* — `CellRef` itself lives in `internal/shared/` and is fine. Narrow the plan's boundary statement.

## 4. D8 wrapper economy — too rigid

Public-only wrappers is too strict. Keep that rule for trivial accessors, but preserve semantic wrappers where fan-out is high or where the wrapper names a protocol — `pull_verify`, tracking begin/end/finish, `top_active_query`, propagation verbs. These are used across many call sites: `cells/memo.mbt:422`, `cells/hybrid_memo.mbt:121`, `cells/push_reactive.mbt:63`, `cells/push_effect.mbt:39`, `cells/signal.mbt:227`, `cells/accumulator.mbt:403`. Forcing all to `@kernel.foo(rt.core, rt.pull, ...)` shrinks `runtime.mbt` but makes the protocol surface harder to read everywhere else. Trade wrong way.

## Blind spots Codex found

- **`guard_dispose` is pure coordinator logic** over `phase` and `tracking.stack` (`cells/runtime.mbt:713`); it moves cleanly. The audit left it open; the code is definitive. → Close the open item.
- **`slot_snapshots()` allocation** — plan assumes zero-copy `Array[&SlotSnapshot]`; not verified. Add a Stage 2 sub-task to confirm MoonBit's trait-object array construction semantics.
- **Whitebox test migration blocker.** `cells/batch_wbtest.mbt:323` calls `commit_batch` directly. Wrapper removal timing needs to track test moves, not just production call sites — already implied by the plan's "whitebox tests migrate with subjects" rule, but the D8 wrapper sweep in Stage 5 must re-check whitebox test call sites too.

## Recommended plan + audit edits (for v3)

**Plan (`2026-04-21-r1-engine-package-split.md`):**

1. **D4 + Stage 2 + Package Layout:** replace `push_revised_at() -> Revision` with `push_revised_at_for(CellId) -> Revision` in the SlotSnapshot trait signature.
2. **Stage 2 state move list:** add `enter_phase`, `leave_phase` explicitly.
3. **Stage 3 ordering:** either exclude `finish_tracking` from 3c (stays behind a wrapper until 3d or later), or swap so subscriber_diff moves first (3c) and tracking moves second.
4. **Stage 3g:** note that `Runtime::fixpoint` keeps a wrapper until Stage 4, *or* hoist `propagate_changes` + `publish_cell_changes` into Stage 3 before 3g.
5. **Stage 4 dispose:** rewrite `dispose_cell(core, ..., cell_lifecycle)` — as written it violates the kernel dependency boundary. Pick explicitly: (a) dispose coordinator stays partly in `cells/runtime.mbt` (simpler; D8 still applies to the pieces that move), or (b) change `CellLifecycle::dispose_cell` to take `RuntimeCore` + state refs (harder; bigger churn in all 4 `*_lifecycle.mbt` files).
6. **Invariant statement:** narrow "kernel never mentions any concrete cell kind" to "kernel never depends on `cells/`-only state (`SlotMeta`, handles) or handle-specific logic" — `CellRef` variants are fine.
7. **D8 wrapper economy:** soften — keep semantic internal wrappers for high-fan-out protocol verbs (`pull_verify`, `push_tracking`/`pop_tracking`/`finish_tracking`, `top_active_query`, `propagate_changes`). Drop only trivial accessors.
8. **R4 risk row:** downgrade — trait-object dispatch cost is not the risk; `slot_snapshots()` allocation is.

**Audit doc (`2026-04-21-r1-stage0-audits.md`):**

9. Close the `guard_dispose` open item with: *"pure coordinator over `phase` and `tracking.stack` per `cells/runtime.mbt:713`; moves to kernel cleanly."*
10. Add finding: *"Real Stage 4 blocker is `CellLifecycle::dispose_cell(self, rt : Runtime, cell_id)` — the method signature references `Runtime`, not `RuntimeCore`. Resolving requires a plan-level decision (see plan edit #5)."*

## Decision on Stage 1 readiness

- **If the plan adopts edits 1–7** as a v3 revision → Stage 1 (skeleton PR) is green-lit.
- **If edits 1, 3, 4, 5 only** are adopted → Stage 1 can proceed; edits 2, 6, 7 can land as plan-doc commits during Stage 2.
- **Edit 5 is non-negotiable before Stage 4** — but Stage 4 is 3 stages away, so it doesn't block Stage 1.

Minimum required before Stage 1 starts: **edits 1, 3, 4** (SlotSnapshot trait signature, 3c ordering, 3g wrapper). These touch text the early stages will cite.
