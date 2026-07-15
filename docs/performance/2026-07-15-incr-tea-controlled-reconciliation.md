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
| Timer resolution probe | 5 µs with `crossOriginIsolated` enabled |
| Command | `cd examples/incr_tea && npm run bench:controlled-reconcile` |
| Sampling | 9 samples × 200 timed operations per cell |

The benchmark server sends `Cross-Origin-Opener-Policy: same-origin` and
`Cross-Origin-Embedder-Policy: require-corp`. The runner asserts
`crossOriginIsolated` and probes `performance.now()` before collecting results.
Each harness mounts a hidden, attached host containing a flat tree with 0, 100,
1,000, or 10,000 nodes. The first 0, 1, 16, or 256 eligible nodes carry one
controlled descriptor, cycling through `value`, `checked`, `disabled`, and
`selected`. Cells with more controlled properties than nodes are omitted.

The timed window begins after an unrelated model write has scheduled a flush.
It excludes tree construction, mount, browser-property mutation, and model
dispatch. Every timed flush is recorded individually. The report's median and
p95 are computed across all `samples × iterations` flushes, not across sample
means. Sample means remain in raw JSON for comparison with earlier snapshots.

Because the measured timer quantum is 5 µs, a cell is marked `measurable` only
when its operation median is at least 10 timer quanta (50 µs). Cells below that
floor still report their quantized operation values, but their operation-level
tail is not treated as a reliable acceptance result; use the sample-mean values
for those cells instead.

## Results

### Equal view with no browser drift

The cached `Html` is equal and every controlled property already has its
intended value, so reconciliation performs no property writes.

| Nodes | Controlled | Median (µs) | p95 (µs) | Min (µs) | Max (µs) | Tail validity |
|---:|---:|---:|---:|---:|---:|---|
| 0 | 0 | 0.00 | 10.0 | 0.00 | 445 | below 50.0 µs median floor |
| 100 | 0 | 5.00 | 10.0 | 0.00 | 95.0 | below 50.0 µs median floor |
| 100 | 1 | 5.00 | 10.0 | 0.00 | 345 | below 50.0 µs median floor |
| 100 | 16 | 5.00 | 10.0 | 0.00 | 500 | below 50.0 µs median floor |
| 1,000 | 0 | 35.0 | 50.0 | 25.0 | 140 | below 50.0 µs median floor |
| 1,000 | 1 | 35.0 | 55.0 | 25.0 | 240 | below 50.0 µs median floor |
| 1,000 | 16 | 35.0 | 65.0 | 25.0 | 250 | below 50.0 µs median floor |
| 1,000 | 256 | 55.0 | 95.0 | 45.0 | 910 | measurable |
| 10,000 | 0 | 340 | 455 | 290 | 680 | measurable |
| 10,000 | 1 | 340 | 470 | 300 | 715 | measurable |
| 10,000 | 16 | 340 | 455 | 300 | 860 | measurable |
| 10,000 | 256 | 360 | 565 | 335 | 765 | measurable |

### Equal view with deliberate property drift

Before each timed flush, the harness mutates every marked descriptor to its
opposite value and asserts that every descriptor present in the cell is drifted
before timing and restored after the first timed flush in every sample. The
16- and 256-property cells exercise all four descriptor kinds.

| Nodes | Controlled | Median (µs) | p95 (µs) | Min (µs) | Max (µs) | Tail validity |
|---:|---:|---:|---:|---:|---:|---|
| 0 | 0 | 0.00 | 5.00 | 0.00 | 50.0 | below 50.0 µs median floor |
| 100 | 0 | 5.00 | 10.0 | 0.00 | 50.0 | below 50.0 µs median floor |
| 100 | 1 | 5.00 | 10.0 | 0.00 | 65.0 | below 50.0 µs median floor |
| 100 | 16 | 10.0 | 25.0 | 5.00 | 115 | below 50.0 µs median floor |
| 1,000 | 0 | 35.0 | 55.0 | 25.0 | 195 | below 50.0 µs median floor |
| 1,000 | 1 | 35.0 | 50.0 | 25.0 | 135 | below 50.0 µs median floor |
| 1,000 | 16 | 40.0 | 70.0 | 30.0 | 175 | below 50.0 µs median floor |
| 1,000 | 256 | 140 | 225 | 115 | 3,915 | measurable |
| 10,000 | 0 | 335 | 480 | 290 | 660 | measurable |
| 10,000 | 1 | 335 | 485 | 305 | 710 | measurable |
| 10,000 | 16 | 345 | 575 | 295 | 830 | measurable |
| 10,000 | 256 | 455 | 825 | 390 | 5,600 | measurable |

## Finding

The operation-level tail is now directly measured for cells whose median is at
least 10 timer quanta. At 10,000 nodes, no-drift equal-view flushes are
340–360 µs median with 455–565 µs p95; 256 mismatch repairs are 455 µs median
and 825 µs p95. These are below a 16.7 ms frame budget by roughly 20–37×. The
1,000-node/256-property repair cell is also measurable at 140 µs median and
225 µs p95. Smaller cells remain reported with an explicit below-resolution
status rather than an unsupported tail claim.

No renderer optimization is justified by this snapshot; the existing
correctness-first reconciliation remains in place.

The benchmark is reproducible with:

```bash
cd examples/incr_tea
npm install
npx playwright install chromium
npm run bench:controlled-reconcile
```

The raw JSON printed by the command preserves operation count, operation-level
median/p95/min/max, sample means, and the timer-resolution validity status.
Browser and machine variance should be checked before using these numbers as a
regression threshold.
