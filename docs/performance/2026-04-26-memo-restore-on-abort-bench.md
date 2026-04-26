# `memo_restore_on_abort` — TODO Validation Microbenchmark

**Date:** 2026-04-26
**Backend:** wasm-gc (`moon bench --release`)
**Bench file:** `cells/accumulator_restore_bench_wbtest.mbt`
**Validates:** the open performance TODO at [`cells/accumulator.mbt:295-302`](../../cells/accumulator.mbt) — *"O(n²) linear scan of `prev_contributions` during `touched` iteration is negligible at single-digit accumulator counts but should be verified before either keeping or rewriting the loop."*

## Setup

The TODO targets the inner loop in `memo_restore_on_abort`:

```moonbit
for slot_id in touched {
  let mut in_prev = false
  for p in prev_contributions {     // ← O(|prev|) per outer iteration
    if p == slot_id { in_prev = true; break }
  }
  if in_prev { continue }
  ...
}
```

The bench constructs the **worst case for the inner scan**: `prev_contributions` (size N) and `touched_accumulator_slots` (size N) are **disjoint**, so every outer iteration walks the full `prev` array before invoking `clear_new_run_buffer`. This forces `|touched| × |prev| = N²` inner comparisons.

The public abort path (`Memo::get`/`get_result`) cannot be benched directly — `Memo::get_result` converts compute-time `Failure` into a hard `abort` at the API boundary, terminating the process. The bench uses package-internal `begin_tracking` + manual `touched_accumulator_slots` population + direct `memo_restore_on_abort` invocation to measure the function in isolation.

## Measurements

10 × N iteration sweeps; mean ± σ.

| N | mean | σ | per-call growth (vs prev N) |
|----|---|---|---|
| 5 | **0.28 µs** | 0.00 | — |
| 20 | **1.31 µs** | 0.01 | 4× input → 4.7× time |
| 100 | **12.51 µs** | 0.12 | 5× input → 9.5× time |

Each measurement covers the full `memo_restore_on_abort` body — the O(n²) inner loop **plus** the linear setup/callback work (HashSet `add` × N for the touched-slot population, `slot.restore_buffer(cell_id)` × N for prev, `slot.clear_new_run_buffer(cell_id)` × N for touched, plus tracking-frame push/pop).

## Interpretation

The TODO's premise — "negligible at single-digit accumulator counts" — is **confirmed**:

- **N=5** (the realistic case for current drivers — the lambda type-checker uses 1–2 accumulators per memo) the entire abort handler runs in 280 ns.
- **N=20** (a hypothetical "medium driver load") still costs only 1.3 µs per abort.
- **N=100** is **not** a realistic per-memo accumulator count for any planned use case. Even at this synthetic worst case the cost is 12.5 µs.

The growth pattern (5×→9.5× from N=20→N=100) confirms quadratic scaling kicks in as N grows, but the constant factors are small enough that the linear setup work (HashSet ops + per-slot HashMap callbacks) dominates at N ≤ 20. A HashSet rewrite of the `in_prev` check would save roughly 4–5 µs at N=100, ~0.1 µs at N=20, and nothing measurable at N=5.

## Decision

**Do not optimize.** The TODO stays open as a "watch this if N grows" marker, but the cost is not actionable at any realistic accumulator count.

**Reopen criteria** (when the optimization becomes worth doing):
- A driver that produces memos accumulating into 50+ slots **and** aborts frequently (re-bench the realistic scenario, not the synthetic disjoint-set worst case)
- Or a profile of a real workload that points to this function

The bench file is kept committed so it can be re-run if either condition appears.

## Reproduce

```bash
moon bench --release -p dowdiness/incr/cells -f accumulator_restore_bench_wbtest.mbt
```
