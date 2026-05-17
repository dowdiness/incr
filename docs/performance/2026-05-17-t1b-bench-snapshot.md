# T1b Phase 2 — Commit-Path Bench Snapshot

**Date:** 2026-05-17
**Backend:** wasm-gc (`moon bench --release`)
**Status:** Shipped (Phases 1–2 on branch `refactor/t1b-memo-commit-phase`; Phase 3 docs + tests pending).

Documents the measured commit-path performance of the T1b refactor
([ADR](../decisions/2026-05-17-t1b-memo-commit-phase.md),
[plan](../plans/2026-05-17-t1b-implementation.md)) end-to-end: pre-T1b
reference → Phase 1 (empty dispatch loops) → Phase 2 (atomic switchover
to `AccumulatorCommitHook`) → Phase 2 with lazy-entry fast-path.

## What was measured

A new microbench was added in Phase 1, specifically to isolate commit-path
overhead with no accumulator amortization:

```moonbit
test "memo: no-accumulator recompute fanout" (b : @bench.T) {
  let rt = Runtime::Runtime()
  let sig = Signal::Signal(rt, 0)
  let memos : Array[Memo[Int]] = []
  for i = 0; i < 50; i = i + 1 {
    memos.push(Memo::Memo(rt, () => sig.get()))
  }
  for i = 0; i < 50; i = i + 1 { ignore(rt.read(memos[i])) } // prime
  let mut v = 0
  b.bench(fn() {
    v = v + 1
    sig.set(v)
    for i = 0; i < 50; i = i + 1 { b.keep(rt.read(memos[i])) }
  })
}
```

50 pure-pull memos that touch no accumulator API. The b.bench loop bumps the
signal once per iteration, then reads all 50 memos (forcing recompute of each).
Per-iteration cost ≈ 50× per-recompute commit-path work.

The bench at `tests/bench_test.mbt` retains the recorded baseline in a
docstring at the test definition.

## Per-stage measurements

All numbers from the same machine within minutes of each other (`moon bench
--release`, 10×N runs per row). The pre-T1b reference was captured by
cherry-picking only the bench-row addition onto pre-T1b main (12a6042) in a
scratch worktree, then discarded.

| Bench                                  | pre-T1b   | Phase 1 (empty) | Phase 2 pre-fix | Phase 2 + fast-path |
|----------------------------------------|----------:|----------------:|----------------:|--------------------:|
| memo: no-accumulator recompute fanout  | 26.70 µs  | 25.41 µs        | 29.47 µs        | **19.82 µs**        |
| memo: wide fanout (1 signal, 50 memos) | 25.81 µs  | 25.37 µs        | 29.79 µs        | **21.37 µs**        |
| memo: deep chain (100 levels, stale)   | 39.24 µs  | 40.52 µs        | 48.53 µs        | **29.50 µs**        |
| baseline: push propagation 100 live    | 22.27 µs  | 21.24 µs        | 20.41 µs        | 20–32 µs (noisy)    |

| Stage delta vs pre-T1b   | no-accumulator | wide fanout | deep chain |
|--------------------------|---------------:|------------:|-----------:|
| Phase 1 (empty dispatch) | −4.8%          | −1.7%       | +3.3%      |
| Phase 2 pre-fix          | +10.4%         | +15.4%      | +23.7%     |
| **Phase 2 + fast-path**  | **−25.7%**     | **−17.2%**  | **−24.8%** |

Push propagation is unaffected by the hook (push reactives don't go through
`memo_force_recompute`). The 20–32 µs noise on that row is environmental
(WSL2 background load); successive runs showed mean ranges from 20.41 µs to
32.14 µs ± 12.42 µs σ in a single bench session.

## Why the fast-path beats pre-T1b

Pre-T1b's `memo_commit_accumulator_phase` (deleted in commit 5290fef) ran
unconditionally per memo recompute and always:

- allocated an empty `@hashset.HashSet[AccumulatorId]` for `all_slots`
- iterated `prev_contributions` into it (no-op when empty)
- allocated an empty `@hashset.HashSet[AccumulatorId]` for `new_contributions`
- called `cell.accumulator_reads.clear()` (HashMap iteration even when empty)
- branched on `new_contributions.is_empty()` → `rt.accumulator_contributions.remove(cell_id)`

For a memo recompute that touched no accumulator, all of this work was wasted.
Estimated per-recompute overhead: ~110 ns × 50 recomputes ≈ 5.5 µs per bench
iteration — which matches the observed Phase 2-pre-fix minus Phase 2-with-
fast-path delta (29.47 − 19.82 = 9.65 µs, ~190 ns/recompute including hook
HashMap ops).

The post-T1b fast-path (`commit-hook adb31f9`) short-circuits all three hook
methods when `rt.accumulator_slots.is_empty()`, paying only one length check
per recompute. Push paths (`Accumulator::push`, `Memo::accumulated`,
`Memo::accumulated_result`) lazy-create the per-cell hook entry on first use,
preserving the "register an accumulator mid-recompute then push" edge case.

## Lessons recorded

1. **Empty dispatch loops have measurable cost.** Phase 1's three empty
   `for hook in []` loops added ~80 ns per memo recompute (50-fanout bench
   showed +3.3% on deep chain, masked by run-to-run noise on flatter rows).
   See `feedback_re_run_benches_before_gate.md` in agent memory: σ on µs
   benches routinely overlaps ±5% threshold; two-of-two run before acting.

2. **"Preserve perf" gates against pre-refactor baselines reveal hidden
   per-iter costs.** Plan compared Phase 2 against Phase 1 (empty-dispatch)
   and would have called the +17% regression a defect — instead, the
   regression flushed out pre-T1b's own per-recompute HashSet allocations,
   and the fix beat both baselines. See `feedback_perf_gate_baseline_audit.md`:
   audit per-iter cost of the existing path, not just algorithmic complexity.

3. **Bench-the-thing-you're-changing.** The new `memo: no-accumulator
   recompute fanout` row was the canonical signal at every stage. The two
   broader rows (wide fanout, deep chain) tracked similarly but with more
   noise. A bench specifically designed for the change-under-test is worth
   adding as part of the change.

## Cross-references

- ADR: [`docs/decisions/2026-05-17-t1b-memo-commit-phase.md`](../decisions/2026-05-17-t1b-memo-commit-phase.md)
- Plan: [`docs/plans/2026-05-17-t1b-implementation.md`](../plans/2026-05-17-t1b-implementation.md)
- Commits on `refactor/t1b-memo-commit-phase`:
  - 267c763 — Phase 1: trait + empty dispatch + bench
  - d93e879 — Phase 1: comment polish
  - 5290fef — Phase 2: atomic switchover
  - adb31f9 — Phase 2: lazy-entry fast-path
- Related earlier perf work:
  [`2026-05-16-tracking-buffer-lazy-alloc.md`](2026-05-16-tracking-buffer-lazy-alloc.md)
  (lazy-allocated the two `ActiveQuery` accumulator fields; T1b Phase 2
  removes those fields entirely and re-locates the work on the hook).
