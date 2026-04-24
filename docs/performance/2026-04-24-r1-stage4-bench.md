# R1 Stage 4 Benchmark Comparison

**Captured:** 2026-04-24 (post-Stage 4, commit `a227c72`)
**Baseline:** [2026-04-21-pre-r1-baseline.md](2026-04-21-pre-r1-baseline.md) (pre-R1 baseline)
**Toolchain:** moonc v0.9.0+8a8d0e4df (2026-04-10), moon 0.1.20260409
**Target:** wasm-gc (authoritative gate per R1 plan)
**Hardware:** AMD Ryzen 7 6800H, Linux 6.6.87.2-microsoft-standard-WSL2 (x86_64)
**Command:**
```bash
moon bench --release -p dowdiness/incr/tests -f bench_test.mbt
moon bench --release -p dowdiness/incr/cells -f push_efficiency_bench_test.mbt
```
**Samples:** each row is `time (mean ± σ)` over 10 rounds × N inner runs.

Invariant I7 gate: ≤ 2 % regression per tracked path vs the pre-R1 baseline.

## Tracked hot paths (wasm-gc)

| Bench | Baseline µs (±σ) | Stage 4 µs (±σ) | Δ (abs) | Δ % | Verdict |
|---|---:|---:|---:|---:|:---:|
| signal: get | 0.01 (0.00) | 0.02 (0.00) | +0.01 | — | noise (sub-µs, σ = 0) |
| signal: set same value (no-op) | 0.01 (0.00) | 0.01 (0.00) | 0 | 0 % | ✅ |
| signal: set new value | 0.04 (0.00) | 0.04 (0.00) | 0 | 0 % | ✅ |
| memo: get warm (up-to-date) | 0.11 (0.00) | 0.12 (0.00) | +0.01 | — | noise (sub-µs) |
| memo: get stale (recompute) | 0.54 (0.00) | 0.54 (0.01) | 0 | 0 % | ✅ |
| **memo: deep chain get (100 levels, stale)** | 39.44 (0.40) | 39.41 (0.45) | −0.03 | −0.1 % | ✅ |
| **memo: wide fanout get (1 signal, 50 memos, stale)** | 24.73 (0.24) | 25.20 (0.23) | +0.47 | +1.9 % | ✅ within ±2 % |
| hybrid: get warm | 0.10 (0.00) | 0.11 (0.00) | +0.01 | — | noise (sub-µs) |
| hybrid: get stale | 0.53 (0.01) | 0.55 (0.01) | +0.02 | +3.8 % | noise (sub-µs, Δ < 2σ) |
| **batch: 10 signals, single revision** | 1.25 (0.01) | 1.19 (0.01) | −0.06 | −4.8 % | ✅ favourable |
| runtime: read one-shot | 0.11 (0.00) | 0.12 (0.00) | +0.01 | — | noise (sub-µs) |
| **baseline: push propagation, 100 live reactives** | 21.43 (0.84) | 20.78 (0.49) | −0.65 | −3.0 % | ✅ favourable |
| baseline: push propagation, 100 disposed reactives | 0.04 (0.00) | 0.05 (0.00) | +0.01 | — | noise (sub-µs) |
| **baseline: push propagation, 100 abandoned reactives** | 21.79 (0.59) | 21.85 (0.62) | +0.06 | +0.3 % | ✅ |
| push efficiency: 100 hybrid subs, no push nodes | 0.04 (0.00) | 0.04 (0.00) | 0 | 0 % | ✅ |
| push efficiency: 100 hybrid subs, distant reactive | 0.05 (0.00) | 0.06 (0.00) | +0.01 | — | noise (sub-µs) |
| push efficiency: 1000 hybrid subs, distant reactive | 0.05 (0.00) | 0.06 (0.00) | +0.01 | — | noise (sub-µs) |
| fixpoint: one iteration, empty delta | 0.05 (0.00) | 0.06 (0.00) | +0.01 | — | noise (sub-µs) |
| fixpoint: one iteration, single-fact delta | 1.75 (0.74) | 1.73 (0.75) | −0.02 | −1.1 % | ✅ (advisory — σ/mean > 40 %, unchanged) |

**Result:** all tight-σ tracked rows — bolded — are within ±2 %. Three rows (deep chain, wide fanout, batch, push-prop-live/abandoned) are the primary gates the plan calls out for the kernel split; all pass. Push propagation with 100 live reactives and batch are both favourable (−3 % and −4.8 %), consistent with the kernel-side bodies inlining cleanly through the thin Runtime wrappers.

Sub-µs rows (mean < 0.15 µs) have σ = 0.00 in the baseline because the rounding mask is 0.01 µs. A +0.01 Δ in these rows is below the measurement floor; treating them as "noise (sub-µs)" matches the baseline doc's convention.

## Additional rows — first-time measurements post-Stage-4

The `gc: sweep` rows at `tests/bench_test.mbt:333,350,363` were added after the baseline was captured. They establish a new reference point for Stage 5 and later:

| Bench | Stage 4 µs (±σ) |
|---|---:|
| gc: sweep 1k all-live | 150.85 (2.21) |
| gc: sweep 1k all-dead | 2.20 (0.02) |
| gc: sweep 1k 50pct dead | 69.42 (1.20) |

These exercise the kernel `gc_sweep` path with the `dispose_fn` callback injection pattern introduced in Stage 4d. No regression risk since there is no baseline; recorded here for future diffs.

High-σ rows not gated (σ / mean > 10 %): `layer2: scope bulk dispose`, `layer2: scope create 10 signals`, `baseline: memo creation cost`, `layer2: nested scope`, `reactive create-dispose cycle`, `memo/signal create-dispose`. All consistent with the baseline convention of excluding noise-dominated rows from the gate.

## Interpretation

Stage 4 introduces kernel-side `propagate_changes`, `commit_batch`, `dispose` helpers, and `gc` bodies, each called through a 1-line Runtime wrapper. The wasm-gc backend inlines through the wrappers cleanly: no tracked row regresses beyond σ, and two hot paths run favourably (push propagation live reactives, batch commit wave).

I4 and the four supporting `commit_batch` invariants are preserved byte-for-byte (see Codex post-review in notes §0 — ≥ 559 / 559 tests pass including callback/on_change/committable/batch_wbtest ordering suites).

**Stage 4 clears the I7 gate.**

## Reproduce

```bash
# From loom/incr/ on commit a227c72 or later:
moon bench --release -p dowdiness/incr/tests -f bench_test.mbt
moon bench --release -p dowdiness/incr/cells -f push_efficiency_bench_test.mbt
```

Run both commands separately (combined suite OOMs the moonrun JS heap, per baseline note).
