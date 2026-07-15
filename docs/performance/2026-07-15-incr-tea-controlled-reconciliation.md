# Incremental TEA controlled-property reconciliation benchmark — 2026-07-15

This snapshot measures the equal-view path added by PR #393 and investigated in
issue #394. The benchmark uses the production `BrowserRenderer::flush_all`
path, not the private DOM benchmark root.

## Environment

| Item | Value |
|---|---|
| OS | Linux 6.6.114.1-microsoft-standard-WSL2 |
| MoonBit | 0.1.20260703 (`6fbf8c3`) |
| JS runtime | Node v24.14.1 |
| Browser | Chromium 148.0.7778.96 via Playwright 1.60.0 |
| Command | `cd examples/incr_tea && npm run bench:controlled-reconcile` |
| Sampling | 9 samples × 200 timed operations per cell |

The benchmark page keeps `requestAnimationFrame` from invoking callbacks and
manually calls `BrowserRenderer::flush_all`. Each harness mounts a hidden,
attached host containing a flat tree with 0, 100, 1,000, or 10,000 nodes. The
first 0, 1, 16, or 256 eligible nodes carry one controlled descriptor, cycling
through `value`, `checked`, `disabled`, and `selected`. Cells with more
controlled properties than nodes are omitted.

The timed window begins after an unrelated model write has scheduled a flush.
It excludes tree construction, mount, browser-property mutation, and model
dispatch. Each sample is the mean of its timed operations. The table reports the
median and p95 across those sample means; min/max show run spread.

## Results

### Equal view with no browser drift

This is the getter/traversal control: the cached `Html` is equal and every
controlled property already has its intended value, so reconciliation performs
no property writes.

| Nodes | Controlled | Median (µs) | p95 (µs) | Min (µs) | Max (µs) |
|---:|---:|---:|---:|---:|---:|
| 0 | 0 | 1.50 | 12.0 | 0.50 | 12.0 |
| 100 | 0 | 4.50 | 18.5 | 3.00 | 18.5 |
| 100 | 1 | 4.50 | 6.50 | 3.50 | 6.50 |
| 100 | 16 | 5.50 | 8.00 | 3.50 | 8.00 |
| 1,000 | 0 | 36.0 | 60.5 | 33.0 | 60.5 |
| 1,000 | 1 | 32.0 | 39.0 | 30.0 | 39.0 |
| 1,000 | 16 | 35.5 | 37.5 | 33.5 | 37.5 |
| 1,000 | 256 | 62.0 | 71.5 | 56.5 | 71.5 |
| 10,000 | 0 | 345 | 404 | 337 | 404 |
| 10,000 | 1 | 348 | 359 | 338 | 359 |
| 10,000 | 16 | 354 | 403 | 344 | 403 |
| 10,000 | 256 | 360 | 364 | 353 | 364 |

### Equal view with deliberate property drift

Before each timed flush, the harness mutates every marked descriptor to its
opposite value and asserts that every descriptor present in the cell is drifted
before timing and restored after the first timed flush in every sample. The
16- and 256-property cells exercise all four descriptor kinds.

| Nodes | Controlled | Median (µs) | p95 (µs) | Min (µs) | Max (µs) |
|---:|---:|---:|---:|---:|---:|
| 0 | 0 | 0.50 | 2.00 | 0.00 | 2.00 |
| 100 | 0 | 4.00 | 7.50 | 2.00 | 7.50 |
| 100 | 1 | 5.00 | 6.50 | 3.00 | 6.50 |
| 100 | 16 | 11.5 | 15.0 | 8.00 | 15.0 |
| 1,000 | 0 | 32.5 | 38.5 | 28.5 | 38.5 |
| 1,000 | 1 | 34.5 | 38.0 | 32.0 | 38.0 |
| 1,000 | 16 | 43.0 | 49.5 | 37.0 | 49.5 |
| 1,000 | 256 | 146 | 187 | 131 | 187 |
| 10,000 | 0 | 346 | 370 | 340 | 370 |
| 10,000 | 1 | 342 | 357 | 332 | 357 |
| 10,000 | 16 | 362 | 375 | 353 | 375 |
| 10,000 | 256 | 464 | 487 | 450 | 487 |

## Finding

The claimed traversal cost is measurable at 10,000 nodes: approximately
0.35–0.36 ms median with no drift and 0.46 ms median for 256 mismatch repairs
on this Chromium run. The bounded traversal is below a 16.7 ms frame budget by
roughly 35× at the largest measured tree, while mismatch repair adds about
0.10 ms at the densest measured case. No optimization is justified by this
snapshot; the existing correctness-first reconciliation remains in place.

The benchmark is now reproducible with:

```bash
cd examples/incr_tea
npm install
npx playwright install chromium
npm run bench:controlled-reconcile
```

The raw JSON printed by the command preserves every per-sample mean for later
comparisons. Browser and machine variance should be checked before using these
numbers as a regression threshold.
