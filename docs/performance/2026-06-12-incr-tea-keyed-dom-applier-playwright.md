# Incremental TEA keyed DOM applier — Playwright browser bench — 2026-06-12

Closes the DOM-applier gap from [#242]. The [2026-06-10 pure-layer
snapshot](2026-06-10-incr-tea-vs-dirty-cell-benches.md) measured view
recompute/skip and `plan_keyed_diff` matching under `moon bench`, but could only
estimate the DOM work saved by keyed reuse. This run measures the keyed applier
in Chromium through Playwright.

## Environment

| | |
|---|---|
| Date | 2026-06-12 |
| CPU | AMD Ryzen 7 6800H (WSL2) |
| Toolchain | moon 0.1.20260608 / moonc v0.10.0+e66899a54 |
| JS runtime | Node v24.14.1 |
| Browser | Chromium 148.0.7778.96 via Playwright 1.60.0 |
| Command | `cd examples/incr_tea && INCR_TEA_DOM_BENCH_ITERATIONS=200 INCR_TEA_DOM_BENCH_SAMPLES=9 npm run bench:dom` |

Numbers are mean ± sample standard deviation, in microseconds per timed
operation. Each cell is 9 samples × 200 operations. The benchmark renders an
N-item baseline, times one operation plus the renderer flush, then resets back to
the baseline outside the timing window. The host is attached to the document but
hidden offscreen, so the measurement includes DOM create/insert/move/detach and
listener attachment work, not user-visible paint.

## What is measured

Two renderer modes share the same list row shape (`li > span + input`) and the
same `Program`/watched-view path. Each row input has one pure `on_input`
descriptor so rebuilds pay listener attachment work.

- **Keyed applier**: renders a `KeyedElem` and flushes through the real
  `diff_keyed_children` path. Survivors are reused by key; new nodes are created
  only for new keys; removed keys are detached.
- **Non-keyed rebuild baseline**: renders ordinary positional children and, when
  the view changes, replaces the whole list root. This is the browser-side
  counterpart to the pure benchmark's "zero key reuse" baseline: it pays the DOM
  create/detach/listener cost that keyed reuse is meant to avoid.

## Results

### Keyed applier (µs/op)

| operation | N=16 | N=64 | N=256 |
|---|---:|---:|---:|
| prepend | 35.9 ± 18.2 | 85.6 ± 6.08 | 334 ± 44.9 |
| remove-first | 19.0 ± 1.48 | 72.3 ± 4.02 | 308 ± 18.1 |
| reverse | 20.1 ± 7.56 | 70.3 ± 6.46 | 395 ± 7.59 |

### Non-keyed rebuild baseline (µs/op)

| operation | N=16 | N=64 | N=256 |
|---|---:|---:|---:|
| prepend | 44.5 ± 9.48 | 156 ± 11.6 | 586 ± 28.6 |
| remove-first | 36.6 ± 4.03 | 154 ± 13.6 | 662 ± 26.9 |
| reverse | 43.1 ± 11.4 | 169 ± 10.1 | 670 ± 39.4 |

### Rebuild / keyed ratio

| operation | N=16 | N=64 | N=256 |
|---|---:|---:|---:|
| prepend | 1.24× | 1.82× | 1.75× |
| remove-first | 1.92× | 2.13× | 2.15× |
| reverse | 2.14× | 2.40× | 1.70× |

## Findings

1. **The keyed DOM path wins in the browser for all measured list sizes.** At
   N=256 it saves ~0.25 ms for prepend, ~0.35 ms for remove-first, and
   ~0.28 ms for reverse versus rebuilding the list root.
2. **The measured browser-side saving is smaller than the earlier generic
   estimate.** In this hidden headless Chromium setup, avoiding 256 row rebuilds
   nets hundreds of microseconds, not multiple milliseconds. The previous
   1–10 µs/create estimate should be treated as a coarse browser/app-dependent
   upper range, not a value to plug into this prototype.
3. **Reverse has the smallest large-N margin.** The current keyed applier
   re-appends every keyed child when the list changes, and the pure planner is
   still O(n²). Reverse is the worst case for both. Keying still wins at N=256,
   but only by 1.70×, which keeps the LIS/two-ended planner follow-up justified.
4. **Prepend/remove-first are the clean keyed-reuse wins.** They reuse almost the
   whole list and create/detach one row, so the keyed path stays ~1.8–2.2×
   faster at N=256 even while paying the existing planner cost.

## Reproduction

```bash
cd examples/incr_tea
npm install
npx playwright install chromium   # one-time browser install if needed
npm run bench:dom
```

Set `INCR_TEA_DOM_BENCH_ITERATIONS` and `INCR_TEA_DOM_BENCH_SAMPLES` to change
the sampling budget.

## Raw samples

The command prints raw JSON under a collapsible section. The committed tables
above are the summarized output from the command in the environment table.
