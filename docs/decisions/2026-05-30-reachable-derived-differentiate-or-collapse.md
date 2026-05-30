# ADR: ReachableDerived — Differentiate or Collapse

**Date:** 2026-05-30
**Status:** Proposed
**Driver:** the `typed_spreadsheet` example (boundary over `@incr`)
**Evidence:** spike branch `spike/spreadsheet-reachable-derived`, probe `tests/spike_reachable_probe_test.mbt`
**Builds on:** [2026-05-17 memo-event-observation](2026-05-17-memo-event-observation.md), [2026-05-21 public-api-ideal-naming](2026-05-21-public-api-ideal-naming.md)

This is a target design, not an implementation plan.

## Context

The `typed_spreadsheet` boundary wants, after each operation, to know which
formula cells recomputed, which changed value, and which reverified without
changing — and it wants the answer in its own cell addresses. Today it fakes
this by reading *every* formula cell before and after the operation and diffing
the `changed_at` / `verified_at` revisions it pulls from `Runtime::cell_info`.
That is O(all formula cells) per operation and exists only because the cell
graph is lazy: nothing recomputes until it is read.

The natural fix is to make the visible region *eager* — anchor a push node
(`EagerDerived` / `Effect`) over the cells the UI is showing, let them recompute
as part of the commit, and read the recompute set off the event stream instead
of scanning. `ReachableDerived` looks like the cell type for this: the
[naming ADR](2026-05-21-public-api-ideal-naming.md) describes it as a "lazy
derived value that participates in reachability propagation through eager/rooted
dependents," and `architecture.md` says "what makes it hybrid is *reachability*…
it participates in `push_reachable_count` so that a live `EagerDerived`/`Effect`
subscriber downstream keeps the memo… alive."

A spike was run to confirm the cell-type choice before changing the boundary.
It falsified the premise.

## Finding: `Derived` and `ReachableDerived` are identical today

Measured on the spike branch (`tests/spike_reachable_probe_test.mbt`, four
probes, all green):

| Cell type | Downstream `Effect` anchor? | After an upstream `Input::set`, with no manual read |
|---|---|---|
| `Derived` | no | stays lazy (not fresh, no recompute) |
| `Derived` | yes | **recomputes eagerly** (fresh, Δ1, effect re-ran) |
| `ReachableDerived` | no | stays lazy |
| `ReachableDerived` | yes | **recomputes eagerly** (fresh, Δ1, effect re-ran) |

The two types behave the same, and the source confirms why:

- The read/verify paths are line-for-line identical (`Memo::get_result_inner`
  vs `HybridMemo::read_result_inner`): `None → force_recompute`; `Some(cached)
  → verified_at check → pull_verify`.
- The push BFS and reachability bookkeeping match `PullMemo(i) | HybridMemo(i)`
  in the *same arm* (`internal/kernel/push_propagate.mbt`,
  `internal/kernel/dispatch.mbt`). A plain `Derived` participates in
  `push_reachable_count` exactly like a `HybridMemo`.
- `is_hybrid` is **read by zero behavioral branches** — only asserted by two
  whitebox tests. Even `gc()` cannot distinguish the two.

So `ReachableDerived` is presently a relabeled `Derived` carrying a dead flag.
The eagerness in the probe comes from the **push-node anchor**, not the memo
type; swapping `Derived → ReachableDerived` in the boundary would change
nothing.

**Documentation discrepancy.** `architecture.md` asserts that participating in
`push_reachable_count` is what makes `ReachableDerived` distinct. The code shows
`Derived` participates identically, so that claim is false under the repo's own
"code is the source of truth" rule. Whichever option below is chosen, that
paragraph must be corrected.

## The gap the driver actually exposes

Push propagation does **not** recompute reachable memos. The propagation loop
evaluates only `PushReactive` / `PushEffect`; memos are merely *traversed* to
route to those push nodes, then recomputed lazily when a push node reads them.
A cell type that *earned* the name `ReachableDerived` would recompute itself
**eagerly during push propagation while `push_reachable_count > 0`** — like
`EagerDerived`, but reverting to lazy pull when no live dependent roots it.

That self-recompute is also where the trace becomes cheap. The pull-memo event
stream ([memo-event-observation](2026-05-17-memo-event-observation.md)) fires
`EnteringCompute` / `Completed(elapsed_ns, backdated)` only on an actual
*rebuild*; a `verified_at`-advances-without-rebuild ("verified clean") emits
nothing, yet that is one of the three states the spreadsheet distinguishes. The
push path already emits the richer shape internally
(`EagerDerivedEvaluated { disposition: RecomputedChanged | RecomputedUnchanged,
changed_at_before, changed_at_after }`). A genuine hybrid recompute should emit
the same vocabulary so a trace can read recomputed / changed / verified-clean
off the stream instead of scanning.

## Decision (proposed)

Adopt **option (b): differentiate `ReachableDerived` into a genuine
eager-when-reachable memo.** Target behavior:

1. While `push_reachable_count > 0`, the cell recomputes **eagerly during push
   propagation** (visited like a push node), not lazily on the next read.
2. When `push_reachable_count == 0`, it reverts to today's pure lazy
   pull-verify — unchanged from `Derived`.
3. Each eager recompute emits an evaluation event carrying before/after
   `verified_at` and `changed_at` plus a `rebuilt` flag, so consumers can
   classify recomputed / changed / verified-clean. This unifies the pull and
   push evaluation-event vocabularies.

This makes the type pull its weight (a real behavioral fork keyed on `is_hybrid`
/ reachability) and is exactly what the spreadsheet needs: visible formulas
self-recompute on input change and report it, so the boundary's `trace()` drops
its O(all formulas) scan and the per-cell `cell_info` revision diffing.

**Gating.** Commissioning is gated on the `typed_spreadsheet` boundary (or
another consumer) actually adopting the viewport-anchor pattern and consuming
the events — consistent with this repo's driver-gate discipline. Until a real
driver lands, the safe interim is **option (a)** below, recorded as the fallback
rather than carrying an inert duplicate type indefinitely.

## Alternatives considered

**(a) Collapse / deprecate `ReachableDerived`.** Since it is `Derived` with a
dead flag, deprecate the type (and `HybridMemo`) and route callers to `Derived`.
Shrinks the public surface and removes a distinction that does not exist.
Rejected as the *primary* proposal only because the spreadsheet driver names a
real behavior the type *should* have; chosen as the fallback if no driver
materializes. Reversible: re-introducing a differentiated type later is additive.

**(c) Keep the type, fix only the docs.** Correct `architecture.md` to state
that `ReachableDerived` is, today, behaviorally identical to `Derived` and
reserved as a push/pull boundary marker (design principle: reserve an extension
point rather than break the API later). Honest and cheap, but leaves a type
whose only content is intent — types should encode behavior, not annotation.
Acceptable only as a stopgap paired with (a)'s deprecation note or (b)'s plan.

## Consequences

- **Semantic shift (option b).** An eager-when-reachable cell recomputes during
  `Input::set` / `batch` commit rather than on read. Reads of an anchored cell
  become "return cached"; the work moves earlier. Off-screen (unrooted) cells
  are unaffected and stay lazy.
- **Event unification.** Pull and push evaluation events converge on one
  vocabulary; the narrow `MemoEvent.Completed` is subsumed or extended (its own
  follow-up; see memo-event-observation ADR's deferred push/batch events).
- **Backdating / `force_set` is a separate concern.** The boundary uses
  `force_set` because its formula payload (a closure) is not `Eq`, so every
  redefinition reverifies even when semantically identical. That is fixed at the
  boundary with a comparable formula fingerprint, independent of this decision;
  it only affects how much the trace reports, not its correctness.
- **Identity is a separate primitive.** Surfacing recompute results in the
  caller's cell addresses (rather than internal `CellId`s) is a distinct
  kinded-`CellTag` design and gets its own ADR; this one assumes it.

## What this unblocks

- The boundary `trace()` rebuilt on the event stream + a viewport anchor,
  removing the per-operation full scan.
- A coherent answer to "lazy vs reachable vs eager" as three *behaviorally
  distinct* points on one axis, instead of two aliases plus one real type.
