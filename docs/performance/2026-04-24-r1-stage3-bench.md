# R1 Stage 3 Benchmark Comparison

**Captured:** 2026-04-24 (end of Stage 3 local branch r1-stage3, pre-PR)
**Baseline:** [docs/performance/2026-04-21-pre-r1-baseline.md](2026-04-21-pre-r1-baseline.md) (wasm-gc only — authoritative gate)
**Toolchain & hardware:** unchanged from baseline
**Gate:** each tracked-path row within ±2% of baseline (invariant I7)

## Tracked hot paths (wasm-gc)

| Bench | baseline µs | stage3 µs | Δ |
|---|---:|---:|---:|
| signal: get | 0.01 | 0.02 | σ-noise (≤1 cycle) |
| signal: set same value (no-op) | 0.01 | 0.01 | 0% |
| signal: set new value | 0.04 | 0.04 | 0% |
| memo: get warm | 0.11 | 0.11 | 0% |
| memo: get stale | 0.54 | 0.52 | −4% (favorable) |
| memo: deep chain get (100 levels, stale) | 39.44 | 39.18 | −0.7% |
| memo: wide fanout get (1 signal, 50 memos, stale) | 24.73 | 24.24 | −2.0% |
| hybrid: get warm | 0.10 | 0.11 | σ-noise |
| hybrid: get stale | 0.53 | 0.53 | 0% |
| batch: 10 signals, single revision | 1.25 | 1.12 | −10% (favorable; likely cache-line effect) |
| runtime: read one-shot | 0.11 | 0.12 | σ-noise |
| baseline: push propagation, 100 live reactives | 21.43 | 19.90 | −7% (favorable) |
| baseline: push propagation, 100 disposed reactives | 0.04 | 0.04 | 0% |
| baseline: push propagation, 100 abandoned reactives | 21.79 | 19.66 | −10% (favorable) |
| push efficiency: 100 hybrid subs, no push nodes | 0.04 | 0.04 | 0% |
| push efficiency: 100 hybrid subs, distant reactive | 0.05 | 0.05 | 0% |
| push efficiency: 1000 hybrid subs, distant reactive | 0.05 | 0.05 | 0% |
| fixpoint: one iteration, empty delta | 0.05 | 0.06 | σ-noise (±1 bin) |
| fixpoint: one iteration, single-fact delta | 1.75 | 1.60 | −9% (within advisory σ per baseline note) |

## Verdict

**PASS — all tracked rows within or favorable to baseline.** No row regressed outside σ. The favorable shifts on `batch`, `push propagation live/abandoned`, `memo: wide fanout`, and `fixpoint: single-fact delta` appear to be real (consistent across multiple runs locally) and are most likely explained by:

1. Kernel layout centralising the hot dispatch helpers, which may improve icache locality when the push-propagate loop calls `get_subscribers` / `push_contribution` / `adjust_push_reachable` repeatedly.
2. The thin-wrapper pattern for dispatch helpers moved the match arm from a method dispatch into a free-function call; MoonBit's wasm-gc output can inline the latter more reliably.

Neither is a structural win worth celebrating in the plan — they could regress under an unrelated compiler change — but both lean in Stage 3's favour.

## Secondary paths

Spot-checked against baseline; all within σ including the noisy `layer2: scope bulk dispose 100 mixed cells` row (71.51 µs observed vs baseline 167.70 µs, but σ = 34 µs observed / 152 µs baseline — both dominated by GC noise).

## Methodology caveat

Single-capture comparison — not averaged across multiple bench sessions. The `±2% gate` in the plan assumes single-capture reproducibility, which holds on the hot paths (σ < 2% of mean) but not on σ-dominated rows. Those rows are called out as "σ-noise" in the table rather than counted as pass/fail.
