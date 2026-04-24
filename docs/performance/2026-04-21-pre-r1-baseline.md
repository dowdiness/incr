# Pre-R1 Benchmark Baseline

**Captured:** 2026-04-24 (Stage 0 of [R1 kernel split plan](../plans/2026-04-21-r1-engine-package-split.md))
**Commit:** dc07e27 (release v0.5.0), clean worktree `r1/stage0-prereqs`
**Toolchain:** moonc v0.9.0+8a8d0e4df (2026-04-10), moon 0.1.20260409, target: native (wasm-gc OOMs on this bench suite — see note below)
**Hardware:** AMD Ryzen 7 6800H, Linux 6.6.87.2-microsoft-standard-WSL2 (x86_64)
**Command:** `moon bench --release --target native`
**Samples:** each row is `time (mean ± σ)` over 10 rounds × N inner runs

This is the reference point against which every R1 Stage 3 sub-step and the Stage 4 PR must diff (invariant I7: ≤2% regression per tracked path). Stages 1 and 2 are file moves only and are also expected to stay within ±1%.

## Why native, not wasm-gc

`moon bench --release` on the default wasm-gc target OOMs the moonrun JS heap on this suite (32 benches × 10 rounds of 100k runs saturates V8's ~1.4 GB default heap). Native target runs identically otherwise. Stage 3 comparisons MUST use `--target native` to stay apples-to-apples.

## Tracked hot paths (Stage 3 gate)

These are the rows the plan calls out and the rows most likely to drift under parameter-passing overhead from the kernel split.

| Bench | Mean (µs) | ±σ |
|---|---:|---:|
| signal: get | 0.11 | 0.00 |
| signal: set same value (no-op) | 0.06 | 0.00 |
| signal: set new value | 0.43 | 0.00 |
| memo: get warm (up-to-date, no recompute) | 1.33 | 0.01 |
| memo: get stale (signal changed, recompute) | 4.49 | 0.04 |
| memo: deep chain get (100 levels, stale) | 286.92 | 0.84 |
| memo: wide fanout get (1 signal, 50 memos, stale) | 201.33 | 2.66 |
| hybrid: get warm | 1.32 | 0.00 |
| hybrid: get stale | 4.46 | 0.03 |
| batch: 10 signals, single revision | 10.93 | 0.06 |
| runtime: read one-shot | 1.33 | 0.01 |
| baseline: push propagation, 100 live reactives | 138.46 | 2.53 |
| baseline: push propagation, 100 disposed reactives | 0.39 | 0.00 |
| baseline: push propagation, 100 abandoned reactives | 148.03 | 2.73 |
| push efficiency: 100 hybrid subs, no push nodes | 0.39 | 0.00 |
| push efficiency: 100 hybrid subs, distant reactive | 0.55 | 0.01 |
| push efficiency: 1000 hybrid subs, distant reactive | 0.56 | 0.00 |

## Secondary paths (informational)

| Bench | Mean | ±σ |
|---|---:|---:|
| baseline: signal.set, clean runtime | 0.43 µs | 0.00 µs |
| baseline: signal.set, 10k unreferenced memos | 0.42 µs | 0.00 µs |
| baseline: memo creation cost (SoA growth) | 0.93 µs | 0.43 µs |
| baseline: reactive create-dispose cycle | 4.95 µs | 0.59 µs |
| layer1: memo create-dispose cycle | 5.88 µs | 0.45 µs |
| layer1: signal create-dispose cycle | 1.06 µs | 0.36 µs |
| layer2: scope create+dispose (empty) | 0.12 µs | 0.00 µs |
| layer2: scope create 10 signals + dispose | 10.42 µs | 3.42 µs |
| layer2: scope bulk dispose 100 mixed cells | 130.92 µs | 50.04 µs |
| layer2: nested scope (3 levels) create+dispose | 3.90 µs | 0.73 µs |
| observer: get warm (memo) | 0.31 µs | 0.00 µs |
| observer: observe + dispose cycle | 1.36 µs | 0.02 µs |
| gc: sweep 1k all-live | 1.31 ms | 11.24 µs |
| gc: sweep 1k all-dead | 12.68 µs | 0.11 µs |
| gc: sweep 1k 50pct dead | 690.86 µs | 6.57 µs |

## Notes for Stage 3 re-runs

- Re-measure on the **same host**, WSL2 can add 5–10% noise session-to-session. Compare deltas, not absolute numbers.
- Benches with σ/mean > 10% (`baseline: memo creation cost`, `layer1 signal create-dispose`, `layer2 scope bulk dispose`) are noise-dominated — don't gate on them. Focus gates on the tight-σ rows above.
- Raw digest: `/tmp/r1-bench-digest.txt` (transient; re-run `moon bench --release --target native` to reproduce).
