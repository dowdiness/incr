# Pre-R1 Benchmark Baseline

**Captured:** 2026-04-24 (Stage 0 of [R1 kernel split plan](../plans/2026-04-21-r1-engine-package-split.md))
**Commit:** dc07e27 (release v0.5.0) with the two new fixpoint benches added locally
**Toolchain:** moonc v0.9.0+8a8d0e4df (2026-04-10), moon 0.1.20260409
**Target:** wasm-gc (the `moon bench` default — matches [historical benchmarks.md](benchmarks.md) convention)
**Hardware:** AMD Ryzen 7 6800H, Linux 6.6.87.2-microsoft-standard-WSL2 (x86_64)
**Command:** run per-bench-file to avoid OOM (see note below)
**Samples:** each row is `time (mean ± σ)` over 10 rounds × N inner runs

This is the reference point against which every R1 Stage 3 sub-step and the Stage 4 PR must diff (invariant I7: ≤2% regression per tracked path). Stages 1 and 2 are file moves only and are also expected to stay within ±1%.

## Filename note

File is dated `2026-04-21` to match the R1 plan's reference anchor (the plan was drafted on that date); capture happened on 2026-04-24 during Stage 0 execution. The convention in `docs/performance/` is dated-by-capture, so this file is a deliberate exception — the Stage 3 sub-steps cite this filename in the plan and the fixed name prevents drift.

## How to re-run for Stage 3 comparison

The combined suite OOMs the moonrun JS heap because `cells/push_efficiency_bench_test.mbt` (3 benches) plus `tests/bench_test.mbt` (31 benches) together exceed V8's ~1.4 GB default. Run them separately:

```bash
moon bench --release -p dowdiness/incr/tests -f bench_test.mbt
moon bench --release -p dowdiness/incr/cells -f push_efficiency_bench_test.mbt
```

**If wasm-gc starts failing for other reasons**, `--target native` is a valid fallback but runs ~10× slower on this workload (MoonBit's native backend does not yet inline and optimize the cell-dispatch hot paths the way wasm-gc + V8 does). Target change invalidates this baseline — recapture on the new target at a fresh dated file.

## Tracked hot paths (Stage 3 gate)

These are the rows the plan calls out and the rows most likely to drift under parameter-passing overhead from the kernel split.

| Bench | Mean (µs) | ±σ |
|---|---:|---:|
| signal: get | 0.01 | 0.00 |
| signal: set same value (no-op) | 0.01 | 0.00 |
| signal: set new value | 0.04 | 0.00 |
| memo: get warm (up-to-date) | 0.11 | 0.00 |
| memo: get stale (recompute) | 0.54 | 0.00 |
| memo: deep chain get (100 levels, stale) | 39.44 | 0.40 |
| memo: wide fanout get (1 signal, 50 memos, stale) | 24.73 | 0.24 |
| hybrid: get warm | 0.10 | 0.00 |
| hybrid: get stale | 0.53 | 0.01 |
| batch: 10 signals, single revision | 1.25 | 0.01 |
| runtime: read one-shot | 0.11 | 0.00 |
| baseline: push propagation, 100 live reactives | 21.43 | 0.84 |
| baseline: push propagation, 100 disposed reactives | 0.04 | 0.00 |
| baseline: push propagation, 100 abandoned reactives | 21.79 | 0.59 |
| push efficiency: 100 hybrid subs, no push nodes | 0.04 | 0.00 |
| push efficiency: 100 hybrid subs, distant reactive | 0.05 | 0.00 |
| push efficiency: 1000 hybrid subs, distant reactive | 0.05 | 0.00 |
| **fixpoint: one iteration, empty delta** | 0.05 | 0.00 |
| **fixpoint: one iteration, single-fact delta** | 1.75 | 0.74 |

The two **fixpoint** rows were added in this Stage 0 pass (the original suite had no fixpoint bench; Stage 3g had no gate). The single-fact-delta row has high σ relative to mean because it inserts a fresh fact each iteration and the relation grows unboundedly over the 75k inner runs; treat the 2% gate as advisory on that row.

## Secondary paths (informational)

| Bench | Mean | ±σ |
|---|---:|---:|
| baseline: signal.set, clean runtime | 0.04 µs | 0.00 µs |
| baseline: signal.set, 10k unreferenced memos | 0.04 µs | 0.00 µs |
| baseline: memo creation cost (SoA growth) | 1.33 µs | 0.61 µs |
| baseline: reactive create-dispose cycle | 1.90 µs | 1.49 µs |
| layer1: memo create-dispose cycle | 1.98 µs | 1.01 µs |
| layer1: signal create-dispose cycle | 0.64 µs | 0.60 µs |
| layer2: scope create+dispose (empty) | 0.03 µs | 0.00 µs |
| layer2: scope create 10 signals + dispose | 7.73 µs | 9.01 µs |
| layer2: scope bulk dispose 100 mixed cells | 167.70 µs | 152.69 µs |
| layer2: nested scope (3 levels) create+dispose | 4.06 µs | 2.33 µs |
| observer: get warm (memo) | 0.03 µs | 0.00 µs |
| observer: observe + dispose cycle | 0.11 µs | 0.00 µs |
| gc: sweep 1k all-live | 140.65 µs | 2.95 µs |
| gc: sweep 1k all-dead | 2.35 µs | 0.02 µs |
| gc: sweep 1k 50pct dead | 69.92 µs | 1.77 µs |

## Cross-check vs historical

`docs/performance/benchmarks.md` (2026-03-08, commit `6c4a17c`) recorded `signal: get` at 0.01 µs, `memo: get warm` at 0.02 µs, `batch: 10 signals` at 1.28 µs on the same wasm-gc default. The signal row matches this baseline exactly (0.01 µs). `memo: get warm` has drifted from 0.02 → 0.11 µs (~5× slower) over 6 weeks of development, and `memo: get stale` from 0.28 → 0.54 µs. These are real drifts but are pre-R1 and outside the scope of this gate — noted here so anyone reading this doesn't mistake R1's baseline for the historical one. Batch has stayed flat (1.25 vs 1.28).

## Notes for Stage 3 re-runs

- Re-measure on the **same host** with the **same command invocation** (per-file, wasm-gc). WSL2 CPU scheduling can add variance between sessions; empirically the low-σ rows above reproduce to within ~5% on repeat runs, but run twice if a gate fires with marginal delta.
- Benches with σ/mean > 30% (`layer2: scope create 10 signals`, `layer2: scope bulk dispose 100 mixed cells`, `layer1: signal create-dispose cycle`, the single-fact fixpoint row) are noise-dominated. Don't gate on them — track absolute change but don't block stage progression on their drift.
- **Sample-size vs 2% gate.** `moon bench` defaults to 10 rounds. For rows with σ/mean ≈ 1%, the sample-mean 95% CI is roughly ±0.6% — tight but usable. For marginal 2% gate decisions, rerun the specific bench in isolation to confirm.
- Raw wasm-gc digest: `/tmp/r1-bench-wasmgc-digest.txt` (transient; re-run the two `moon bench` commands above to reproduce).
