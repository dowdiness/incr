# Incremental TEA inactive-root cohort benchmark — 2026-06-15

This snapshot extends the DOM-preserving inactive-root measurements from PRs #275
and #276 to cohort behavior. It is measurement only: it does not change trigger
policy, lifecycle semantics, `Watch` ownership, or the renderer's
`deactivate`/`activate` contract.

The new `workspace-inactive-root-cohort` suite mounts one shared workspace
`Program` into multiple inactive DOM roots. The `Program` owns one shared view
`Watch`; per-root state is the DOM root plus its rendered/last-view cache. The
model state is shared so each burst is one application update stream, not N
independent programs receiving N separate updates.

Per-root subtree size is fixed at N=256. The root-count axis is 1 / 4 / 16. Each
burst performs 10 / 100 / 1000 model updates while all roots are inactive; after
each update the harness walks the inactive `flush_if_active` skip path for every
root. The suite reports both:

- **total burst** — inactive updates plus activation in the timed window;
- **activation only** — the same inactive burst happens before timing, then the
  timed window activates either one root or all roots.

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

| burst | activation | timing | roots | `incr_tea` |
|---|---|---|---:|---:|
| 10 inactive updates | one root | total burst | 1 | 381 ± 64.1 |
| 10 inactive updates | one root | total burst | 4 | 318 ± 15.7 |
| 10 inactive updates | one root | total burst | 16 | 371 ± 10.7 |
| 10 inactive updates | one root | activation only | 1 | 280 ± 9.98 |
| 10 inactive updates | one root | activation only | 4 | 274 ± 10.7 |
| 10 inactive updates | one root | activation only | 16 | 319 ± 6.23 |
| 10 inactive updates | all roots | total burst | 1 | 342 ± 22.3 |
| 10 inactive updates | all roots | total burst | 4 | 854 ± 19.1 |
| 10 inactive updates | all roots | total burst | 16 | 3691 ± 63.5 |
| 10 inactive updates | all roots | activation only | 1 | 281 ± 17.9 |
| 10 inactive updates | all roots | activation only | 4 | 821 ± 31.5 |
| 10 inactive updates | all roots | activation only | 16 | 3552 ± 36.0 |
| 100 inactive updates | one root | total burst | 1 | 670 ± 61.2 |
| 100 inactive updates | one root | total burst | 4 | 610 ± 25.6 |
| 100 inactive updates | one root | total burst | 16 | 688 ± 18.5 |
| 100 inactive updates | one root | activation only | 1 | 288 ± 10.2 |
| 100 inactive updates | one root | activation only | 4 | 289 ± 11.5 |
| 100 inactive updates | one root | activation only | 16 | 344 ± 18.6 |
| 100 inactive updates | all roots | total burst | 1 | 629 ± 23.1 |
| 100 inactive updates | all roots | total burst | 4 | 1190 ± 64.5 |
| 100 inactive updates | all roots | total burst | 16 | 4017 ± 59.4 |
| 100 inactive updates | all roots | activation only | 1 | 329 ± 32.9 |
| 100 inactive updates | all roots | activation only | 4 | 944 ± 50.1 |
| 100 inactive updates | all roots | activation only | 16 | 3802 ± 45.9 |
| 1000 inactive updates | one root | total burst | 1 | 3464 ± 40.8 |
| 1000 inactive updates | one root | total burst | 4 | 3529 ± 81.4 |
| 1000 inactive updates | one root | total burst | 16 | 3590 ± 48.7 |
| 1000 inactive updates | one root | activation only | 1 | 407 ± 23.0 |
| 1000 inactive updates | one root | activation only | 4 | 406 ± 33.6 |
| 1000 inactive updates | one root | activation only | 16 | 426 ± 10.0 |
| 1000 inactive updates | all roots | total burst | 1 | 3491 ± 33.9 |
| 1000 inactive updates | all roots | total burst | 4 | 4223 ± 81.2 |
| 1000 inactive updates | all roots | total burst | 16 | 7198 ± 27.6 |
| 1000 inactive updates | all roots | activation only | 1 | 443 ± 22.8 |
| 1000 inactive updates | all roots | activation only | 4 | 1140 ± 41.0 |
| 1000 inactive updates | all roots | activation only | 16 | 4228 ± 59.8 |

## Interpretation

1. **Activating one root stays near one-root cost.** With 16 inactive roots,
   activation-only for one root is 319 / 344 / 426 µs after 10 / 100 / 1000
   updates. The inactive cohort walk adds some skip overhead, but activation does
   not diff untouched DOM roots.
2. **Activating all roots scales with the number of DOM subtrees.** At 16 roots,
   activation-only is about 3.6–4.2 ms. That is the expected cost of diffing 16
   N=256 hidden workspace DOM trees after the shared model catches up.
3. **Long bursts are dominated by skipped-update work, not activation-one.** For
   1000 updates, one-root activation totals stay around 3.5–3.6 ms for 1 / 4 /
   16 roots; the extra inactive skip checks are small relative to the update burst.
4. **Trigger policy remains out of scope.** These rows answer the cohort cost
   model for shared-program inactive roots. They do not measure independent
   programs each receiving separate update streams, nor do they choose visibility,
   idle, or manual activation policy.

## Reproduction

```bash
NEW_MOON_MOD=0 moon check --deny-warn --target js examples/incr_tea
NEW_MOON_MOD=0 moon check --deny-warn --target js examples/incr_tea/browser_ui_compare_bench
cd examples/incr_tea
npm run bench:ui-compare-dom
```

Set `INCR_TEA_UI_COMPARE_DOM_BENCH_ITERATIONS` and
`INCR_TEA_UI_COMPARE_DOM_BENCH_SAMPLES` to change the sampling budget.
