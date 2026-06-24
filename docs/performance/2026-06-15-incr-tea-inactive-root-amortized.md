# Incremental TEA inactive-root amortized benchmark — 2026-06-15

This snapshot follows the first DOM-preserving inactive-root prototype by timing
bursts of inactive updates before one activation catch-up. It is measurement only:
it does not change trigger policy, visibility semantics, `Watch` ownership, or the
renderer's deactivate/activate contract.

The benchmark extends `npm run bench:ui-compare-dom` with an `incr_tea`-only
`workspace-inactive-root-amortized` suite over the same editor/sidebar/inspector-
shaped subtree used by `workspace-island` and `workspace-inactive-root`:

- **10 inactive updates + activation** — deactivate the mounted root before the
  timed window, perform 10 model updates through the inactive flush-skip path,
  then activate once;
- **100 inactive updates + activation** — same, with 100 inactive updates;
- **1000 inactive updates + activation** — same, with 1000 inactive updates.

The timed window includes the inactive updates and one activation catch-up. Reset
work and the deactivation call run before timing starts. Units in the amortized
rows are microseconds per burst, not per single update.

## Environment

| | |
|---|---|
| Date | 2026-06-15 |
| CPU | AMD Ryzen 7 6800H (WSL2), 8 vCPU |
| Toolchain | moon 0.1.20260608 / moonc v0.10.0+e66899a54 |
| JS runtime | Node v24.14.1 |
| Browser | Chromium 148.0.7778.96 via Playwright 1.60.0 |
| Command | `cd examples/incr_tea && npm run bench:ui-compare-dom` |

Each cell below is 9 samples × 200 timed operations. Units are microseconds,
mean ± sample standard deviation.

## Results

### Single-update reference rows from the same run

| operation | N | `incr_tea` |
|---|---:|---:|
| active hidden-mounted update | 64 | 81.6 ± 5.75 |
| active hidden-mounted update | 256 | 277 ± 5.39 |
| active hidden-mounted update | 512 | 570 ± 25.2 |
| inactive update | 64 | 4.83 ± 2.47 |
| inactive update | 256 | 7.33 ± 1.50 |
| inactive update | 512 | 8.67 ± 2.38 |
| activation catch-up | 64 | 76.1 ± 4.54 |
| activation catch-up | 256 | 286 ± 21.4 |
| activation catch-up | 512 | 581 ± 30.4 |

### Amortized inactive workspace root

| burst | N | `incr_tea` total |
|---|---:|---:|
| 10 inactive updates + activation | 64 | 118 ± 9.36 |
| 10 inactive updates + activation | 256 | 307 ± 6.69 |
| 10 inactive updates + activation | 512 | 615 ± 30.9 |
| 100 inactive updates + activation | 64 | 434 ± 30.7 |
| 100 inactive updates + activation | 256 | 646 ± 31.8 |
| 100 inactive updates + activation | 512 | 969 ± 33.6 |
| 1000 inactive updates + activation | 64 | 3815 ± 192 |
| 1000 inactive updates + activation | 256 | 4144 ± 187 |
| 1000 inactive updates + activation | 512 | 4206 ± 150 |

For scale, multiplying the same-run active hidden-mounted update row by the
number of updates gives the active-root baseline that a hidden mounted root would
pay if it stayed active for every edit. That comparison is computed from the
reference row above, not measured as a separate burst cell.

| burst | N | inactive total | active equivalent | inactive/active |
|---|---:|---:|---:|---:|
| 10 updates + activation | 64 | 118 | 816 | 0.14× |
| 10 updates + activation | 256 | 307 | 2770 | 0.11× |
| 10 updates + activation | 512 | 615 | 5700 | 0.11× |
| 100 updates + activation | 64 | 434 | 8160 | 0.053× |
| 100 updates + activation | 256 | 646 | 27700 | 0.023× |
| 100 updates + activation | 512 | 969 | 57000 | 0.017× |
| 1000 updates + activation | 64 | 3815 | 81600 | 0.047× |
| 1000 updates + activation | 256 | 4144 | 277000 | 0.015× |
| 1000 updates + activation | 512 | 4206 | 570000 | 0.0074× |

## Interpretation

1. **Activation remains the fixed visible-scale cost.** The 10-update burst is
   close to the single activation catch-up row, especially at N=256/512. A short
   inactive interval mostly shifts one visible-scale flush to activation.
2. **Long inactive bursts amortize well.** At 1000 updates, total cost is roughly
   3.8–4.2 ms across N=64/256/512. The skipped updates dominate the total, but
   they stay near a few microseconds each and avoid repeated N-scaled DOM diffs.
3. **The value of inactivity grows with subtree size and update count.** The
   computed active equivalent reaches 570 ms at N=512 for 1000 hidden updates;
   the inactive burst plus activation measured about 4.2 ms in the same run.
4. **Trigger policy is still out of scope.** These rows answer the amortized cost
   model for one inactive root. Visibility, idle, manual activation, and multiple-
   root cohort policy should be designed only after a concrete product shape
   needs them.

## Reproduction

```bash
NEW_MOON_MOD=0 moon check --deny-warn --target js examples/incr_tea
NEW_MOON_MOD=0 moon check --deny-warn --target js examples/incr_tea/browser_ui_compare_bench
cd examples/incr_tea
npm run bench:ui-compare-dom
```

Set `INCR_TEA_UI_COMPARE_DOM_BENCH_ITERATIONS` and
`INCR_TEA_UI_COMPARE_DOM_BENCH_SAMPLES` to change the sampling budget.
