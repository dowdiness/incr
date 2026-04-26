# Pre-R1 Benchmark Baseline

**Captured:** 2026-04-24 (Stage 0 of [R1 kernel split plan](../archive/completed-phases/2026-04-21-r1-engine-package-split.md))
**Commit:** dc07e27 (release v0.5.0) with the two new fixpoint benches added locally
**Toolchain:** moonc v0.9.0+8a8d0e4df (2026-04-10), moon 0.1.20260409
**Target:** wasm-gc (authoritative gate — matches [historical benchmarks.md](benchmarks.md) convention) + js (informational cross-check for `examples/web` consumers)
**Hardware:** AMD Ryzen 7 6800H, Linux 6.6.87.2-microsoft-standard-WSL2 (x86_64)
**Command:** run per-bench-file to avoid OOM (see note below)
**Samples:** each row is `time (mean ± σ)` over 10 rounds × N inner runs

This is the reference point against which every R1 Stage 3 sub-step and the Stage 4 PR must diff (invariant I7: ≤2% regression per tracked path). Stages 1 and 2 are file moves only and are also expected to stay within ±1%.

## Filename note

File is dated `2026-04-21` to match the R1 plan's reference anchor (the plan was drafted on that date); capture happened on 2026-04-24 during Stage 0 execution. The convention in `docs/performance/` is dated-by-capture, so this file is a deliberate exception — the Stage 3 sub-steps cite this filename in the plan and the fixed name prevents drift.

## How to re-run for Stage 3 comparison

The combined suite OOMs the moonrun JS heap because `cells/push_efficiency_bench_test.mbt` (3 benches) plus `tests/bench_test.mbt` (31 benches) together exceed V8's ~1.4 GB default. Run them separately on each target:

```bash
# wasm-gc (Stage 3 gate — default target)
moon bench --release -p dowdiness/incr/tests -f bench_test.mbt
moon bench --release -p dowdiness/incr/cells -f push_efficiency_bench_test.mbt

# js (informational cross-check for examples/web consumers)
moon bench --release --target js -p dowdiness/incr/tests -f bench_test.mbt
moon bench --release --target js -p dowdiness/incr/cells -f push_efficiency_bench_test.mbt
```

**If both wasm-gc and js start failing for other reasons**, `--target native` is a valid fallback but runs ~5–20× slower on this workload (MoonBit's native backend does not yet inline and optimize the cell-dispatch hot paths the way wasm-gc + V8 does). Target change invalidates this baseline — recapture on the new target at a fresh dated file.

## Tracked hot paths (Stage 3 gate — wasm-gc)

These are the rows the plan calls out and the rows most likely to drift under parameter-passing overhead from the kernel split. **wasm-gc is the authoritative gate**; JS column is informational cross-check (relevant for `examples/web` consumers).

| Bench | wasm-gc µs (±σ) | js µs (±σ) |
|---|---:|---:|
| signal: get | 0.01 (0.00) | 0.01 (0.00) |
| signal: set same value (no-op) | 0.01 (0.00) | 0.00 (0.00) |
| signal: set new value | 0.04 (0.00) | 0.03 (0.00) |
| memo: get warm (up-to-date) | 0.11 (0.00) | 0.09 (0.00) |
| memo: get stale (recompute) | 0.54 (0.00) | 0.85 (0.02) |
| memo: deep chain get (100 levels, stale) | 39.44 (0.40) | 67.75 (0.96) |
| memo: wide fanout get (1 signal, 50 memos, stale) | 24.73 (0.24) | 40.47 (0.20) |
| hybrid: get warm | 0.10 (0.00) | 0.08 (0.00) |
| hybrid: get stale | 0.53 (0.01) | 0.85 (0.01) |
| batch: 10 signals, single revision | 1.25 (0.01) | 1.35 (0.01) |
| runtime: read one-shot | 0.11 (0.00) | 0.10 (0.01) |
| baseline: push propagation, 100 live reactives | 21.43 (0.84) | 38.64 (0.65) |
| baseline: push propagation, 100 disposed reactives | 0.04 (0.00) | 0.04 (0.00) |
| baseline: push propagation, 100 abandoned reactives | 21.79 (0.59) | 36.52 (0.27) |
| push efficiency: 100 hybrid subs, no push nodes | 0.04 (0.00) | 0.04 (0.00) |
| push efficiency: 100 hybrid subs, distant reactive | 0.05 (0.00) | 0.06 (0.00) |
| push efficiency: 1000 hybrid subs, distant reactive | 0.05 (0.00) | 0.06 (0.00) |
| **fixpoint: one iteration, empty delta** | 0.05 (0.00) | 0.09 (0.01) |
| **fixpoint: one iteration, single-fact delta** | 1.75 (0.74) | 1.57 (0.33) |

The two **fixpoint** rows were added in this Stage 0 pass (the original suite had no fixpoint bench; Stage 3g had no gate). The single-fact-delta row has high σ relative to mean because it inserts a fresh fact each iteration and the relation grows unboundedly over the 75k inner runs; treat the 2% gate as advisory on that row.

### Target comparison reading

wasm-gc and JS agree on signal-level hot paths (0.01–0.04 µs). JS runs ~1.5–2× slower on heavy memo work (`memo: deep chain`, `memo: wide fanout`, `push propagation, 100 live`) — consistent with V8's closure-allocation cost when running MoonBit-emitted JS vs wasm-gc's flatter dispatch. Both targets are ~5–20× faster than `--target native` on this workload.

## Secondary paths (informational)

| Bench | wasm-gc µs (±σ) | js µs (±σ) |
|---|---:|---:|
| baseline: signal.set, clean runtime | 0.04 (0.00) | 0.04 (0.00) |
| baseline: signal.set, 10k unreferenced memos | 0.04 (0.00) | 0.04 (0.00) |
| baseline: memo creation cost (SoA growth) | 1.33 (0.61) | 1.07 (0.27) |
| baseline: reactive create-dispose cycle | 1.90 (1.49) | 1.64 (0.13) |
| layer1: memo create-dispose cycle | 1.98 (1.01) | 2.13 (0.17) |
| layer1: signal create-dispose cycle | 0.64 (0.60) | 0.41 (0.13) |
| layer2: scope create+dispose (empty) | 0.03 (0.00) | 0.10 (0.00) |
| layer2: scope create 10 signals + dispose | 7.73 (9.01) | 4.75 (1.67) |
| layer2: scope bulk dispose 100 mixed cells | 167.70 (152.69) | 68.56 (20.96) |
| layer2: nested scope (3 levels) create+dispose | 4.06 (2.33) | 2.02 (0.29) |
| observer: get warm (memo) | 0.03 (0.00) | 0.03 (0.01) |
| observer: observe + dispose cycle | 0.11 (0.00) | 0.09 (0.01) |
| gc: sweep 1k all-live | 140.65 (2.95) | 226.52 (2.93) |
| gc: sweep 1k all-dead | 2.35 (0.02) | 4.90 (0.09) |
| gc: sweep 1k 50pct dead | 69.92 (1.77) | 104.79 (1.67) |

## Cross-check vs historical

`docs/performance/benchmarks.md` (2026-03-08, commit `6c4a17c`) recorded `signal: get` at 0.01 µs, `memo: get warm` at 0.02 µs, `batch: 10 signals` at 1.28 µs on the same wasm-gc default. The signal row matches this baseline exactly (0.01 µs). `memo: get warm` has drifted from 0.02 → 0.11 µs (~5× slower) over 6 weeks of development, and `memo: get stale` from 0.28 → 0.54 µs. These are real drifts but are pre-R1 and outside the scope of this gate — noted here so anyone reading this doesn't mistake R1's baseline for the historical one. Batch has stayed flat (1.25 vs 1.28).

## Notes for Stage 3 re-runs

- Re-measure on the **same host** with the **same command invocation** (per-file, wasm-gc). WSL2 CPU scheduling can add variance between sessions; empirically the low-σ rows above reproduce to within ~5% on repeat runs, but run twice if a gate fires with marginal delta.
- Benches with σ/mean > 30% (`layer2: scope create 10 signals`, `layer2: scope bulk dispose 100 mixed cells`, `layer1: signal create-dispose cycle`, the single-fact fixpoint row) are noise-dominated. Don't gate on them — track absolute change but don't block stage progression on their drift.
- **Sample-size vs 2% gate.** `moon bench` defaults to 10 rounds. For rows with σ/mean ≈ 1%, the sample-mean 95% CI is roughly ±0.6% — tight but usable. For marginal 2% gate decisions, rerun the specific bench in isolation to confirm.
- Raw wasm-gc digest: `/tmp/r1-bench-wasmgc-digest.txt` (transient; re-run the two `moon bench` commands above to reproduce).
