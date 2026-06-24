# Incremental TEA independent inactive-root cohort benchmark — 2026-06-16

This snapshot follows the shared-`Program` inactive-root cohort benchmark from
PR #277. That run mounted one workspace `Program` and one view `Watch` into
multiple inactive DOM roots. This run adds the independent-root cohort: every DOM
root owns a separate `ui_compare_incr_workspace_program(runtime, 256)`, and
therefore a separate model, view `Watch`, and rendered/last-view cache.

The benchmark is measurement only. It does not change trigger policy, lifecycle
semantics, `Watch` ownership, or the renderer's `deactivate`/`activate` contract.
The harness reuses `BrowserRenderer::deactivate`, `BrowserRenderer::activate`,
and `BrowserRoot::flush_if_active`.

Per-root subtree size is fixed at N=256. The root-count axis is 1 / 4 / 16. Each
burst performs 10 / 100 / 1000 updates while all roots are inactive. Unlike the
shared cohort, each burst update is broadcast to every root/program, then the
harness walks the inactive `flush_if_active` skip path for every root. The suite
reports both:

- **total burst** — broadcast inactive updates plus activation in the timed
  window;
- **activation only** — the same inactive burst happens before timing, then the
  timed window activates either one root or all roots.

## Environment

| | |
|---|---|
| Date | 2026-06-16 |
| CPU | AMD Ryzen 7 6800H (WSL2), 8 vCPU |
| Toolchain | moon 0.1.20260608 / moonc v0.10.0+e66899a54 |
| JS runtime | Node v24.14.1 |
| Browser | Chromium 148.0.7778.96 via Playwright 1.60.0 |
| Command | `cd examples/incr_tea && npm run bench:ui-compare-dom` |

Each cell below is 9 samples × 200 timed operations. Units are microseconds,
mean ± sample standard deviation.

## Results

| burst | activation | timing | roots | `incr_tea` |
|---|---|---|---:|---:|
| 10 inactive updates | one root | total burst | 1 | 307 ± 14.2 |
| 10 inactive updates | one root | total burst | 4 | 444 ± 12.6 |
| 10 inactive updates | one root | total burst | 16 | 1006 ± 53.8 |
| 10 inactive updates | one root | activation only | 1 | 269 ± 6.20 |
| 10 inactive updates | one root | activation only | 4 | 308 ± 18.9 |
| 10 inactive updates | one root | activation only | 16 | 440 ± 70.2 |
| 10 inactive updates | all roots | total burst | 1 | 307 ± 16.3 |
| 10 inactive updates | all roots | total burst | 4 | 1364 ± 28.3 |
| 10 inactive updates | all roots | total burst | 16 | 7375 ± 69.3 |
| 10 inactive updates | all roots | activation only | 1 | 279 ± 23.4 |
| 10 inactive updates | all roots | activation only | 4 | 1224 ± 19.4 |
| 10 inactive updates | all roots | activation only | 16 | 6832 ± 34.7 |
| 100 inactive updates | one root | total burst | 1 | 597 ± 24.6 |
| 100 inactive updates | one root | total burst | 4 | 1598 ± 34.0 |
| 100 inactive updates | one root | total burst | 16 | 5632 ± 80.4 |
| 100 inactive updates | one root | activation only | 1 | 302 ± 29.2 |
| 100 inactive updates | one root | activation only | 4 | 338 ± 14.2 |
| 100 inactive updates | one root | activation only | 16 | 551 ± 39.7 |
| 100 inactive updates | all roots | total burst | 1 | 634 ± 25.9 |
| 100 inactive updates | all roots | total burst | 4 | 2771 ± 34.5 |
| 100 inactive updates | all roots | total burst | 16 | 13355 ± 213 |
| 100 inactive updates | all roots | activation only | 1 | 305 ± 17.0 |
| 100 inactive updates | all roots | activation only | 4 | 1477 ± 35.9 |
| 100 inactive updates | all roots | activation only | 16 | 7932 ± 132 |
| 1000 inactive updates | one root | total burst | 1 | 3670 ± 82.2 |
| 1000 inactive updates | one root | total burst | 4 | 13282 ± 253 |
| 1000 inactive updates | one root | total burst | 16 | 54908 ± 592 |
| 1000 inactive updates | one root | activation only | 1 | 470 ± 30.2 |
| 1000 inactive updates | one root | activation only | 4 | 601 ± 32.5 |
| 1000 inactive updates | one root | activation only | 16 | 636 ± 64.3 |
| 1000 inactive updates | all roots | total burst | 1 | 3575 ± 63.7 |
| 1000 inactive updates | all roots | total burst | 4 | 14414 ± 77.0 |
| 1000 inactive updates | all roots | total burst | 16 | 59555 ± 253 |
| 1000 inactive updates | all roots | activation only | 1 | 407 ± 44.2 |
| 1000 inactive updates | all roots | activation only | 4 | 1778 ± 100 |
| 1000 inactive updates | all roots | activation only | 16 | 8680 ± 264 |

## Interpretation

1. **Broadcast update fanout dominates total-burst rows.** At 16 independent
   roots, one-root activation totals are 1.01 / 5.63 / 54.9 ms after 10 / 100 /
   1000 inactive updates because each logical burst update is applied to 16
   separate programs.
2. **Activating one root remains bounded by one catch-up root.** At 16 roots,
   activation-only for one root is 440 / 551 / 636 µs after 10 / 100 / 1000
   updates. That is higher than the shared-`Program` cohort, but it is not
   proportional to the number of inactive roots.
3. **Activating all roots now pays per-program verification plus DOM diffing.**
   At 16 roots, activation-only is 6.83 / 7.93 / 8.68 ms. This is the expected
   cost of catching up 16 separate view `Watch` chains and 16 DOM subtrees.
4. **Trigger policy remains out of scope.** These rows answer the independent
   root cost model. They do not choose visibility, idle, manual activation, or
   update-coalescing policy.

## Reproduction

```bash
NEW_MOON_MOD=0 moon check --deny-warn --target js examples/incr_tea
NEW_MOON_MOD=0 moon check --deny-warn --target js examples/incr_tea/browser_ui_compare_bench
cd examples/incr_tea
npm run bench:ui-compare-dom
```

Set `INCR_TEA_UI_COMPARE_DOM_BENCH_ITERATIONS` and
`INCR_TEA_UI_COMPARE_DOM_BENCH_SAMPLES` to change the sampling budget.
