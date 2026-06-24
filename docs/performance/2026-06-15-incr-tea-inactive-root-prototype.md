# Incremental TEA inactive-root prototype benchmark — 2026-06-15

This snapshot follows the #255 activation-islands measurement by timing the first
DOM-preserving inactive-root prototype in `examples/incr_tea`.

The benchmark extends `npm run bench:ui-compare-dom` with an `incr_tea`-only
`workspace-inactive-root` suite over the same editor/sidebar/inspector-shaped
subtree used by `workspace-island`:

- **active hidden-mounted update** — the DOM-present workspace root is active;
  the timed edit reads the watched `Html` and patches the hidden subtree;
- **inactive update** — the workspace root stays mounted and DOM-attached but is
  deactivated; the timed edit dispatches the model update and records an inactive
  flush skip without reading the watched `Html`;
- **activation catch-up** — one edit happens while inactive before the timed
  window; the timed operation activates the root and performs the catch-up flush.

The inactive-root harness drives the renderer's root flush helpers manually so
its timed windows stay comparable to the existing `DomBenchRoot` cells. The
benchmark page uses an immediate `requestAnimationFrame` shim for adjacent
framework measurements; using the renderer's normal on-change rAF listener inside
that shim would measure benchmark-clock reentrancy rather than the inactive-root
state itself.

## Environment

| | |
|---|---|
| Date | 2026-06-15 |
| CPU | AMD Ryzen 7 6800H (WSL2), 8 vCPU |
| Toolchain | moon 0.1.20260608 / moonc v0.10.0+e66899a54 |
| JS runtime | Node v24.14.1 |
| Browser | Chromium 148.0.7778.96 via Playwright 1.60.0 |
| Command | `cd examples/incr_tea && npm run bench:ui-compare-dom` |

Each cell below is 9 samples × 200 operations. Units are microseconds per timed
operation, mean ± sample standard deviation.

## Results

### Existing workspace-island rows from the same run

| operation | N | `incr_tea` |
|---|---:|---:|
| collapsed update | 64 | 4.50 ± 1.20 |
| collapsed update | 256 | 3.94 ± 1.26 |
| collapsed update | 512 | 3.78 ± 0.94 |
| hidden mounted update | 64 | 83.8 ± 12.1 |
| hidden mounted update | 256 | 286 ± 18.8 |
| hidden mounted update | 512 | 551 ± 10.4 |
| visible update | 64 | 74.6 ± 1.92 |
| visible update | 256 | 291 ± 15.2 |
| visible update | 512 | 552 ± 14.6 |

### DOM-preserving inactive workspace root

| operation | N | `incr_tea` |
|---|---:|---:|
| active hidden-mounted update | 64 | 80.2 ± 4.10 |
| active hidden-mounted update | 256 | 296 ± 16.8 |
| active hidden-mounted update | 512 | 545 ± 17.3 |
| inactive update | 64 | 4.33 ± 0.66 |
| inactive update | 256 | 5.50 ± 1.60 |
| inactive update | 512 | 7.17 ± 2.40 |
| activation catch-up | 64 | 74.8 ± 2.70 |
| activation catch-up | 256 | 272 ± 16.1 |
| activation catch-up | 512 | 538 ± 8.17 |

## Interpretation

1. **Inactive updates match collapsed-update scale while preserving DOM.** The
   inactive update row stays around 4–7 µs across N=64/256/512, while active
   hidden-mounted updates in the same run cost roughly 80/296/545 µs.
2. **Activation pays the deferred work once.** Activation catch-up lands close to
   active hidden/visible updates, which is expected: it performs the skipped
   watched-view read and DOM diff after one inactive edit.
3. **The prototype shifts cost from hidden background edits to activation.** This
   supports the #255 direction for visibility/idle/manual triggers: keep
   DOM-present hidden panels cheap while inactive, then catch up when they become
   useful again.
4. **This does not replace collapsed conditionals.** Collapsed workspace updates
   remain equally cheap because dynamic dependencies already avoid reading the
   hidden subtree when it is absent.

## Reproduction

```bash
NEW_MOON_MOD=0 moon check --deny-warn --target js examples/incr_tea
NEW_MOON_MOD=0 moon check --deny-warn --target js examples/incr_tea/browser_ui_compare_bench
cd examples/incr_tea
npm run bench:ui-compare-dom
```

Set `INCR_TEA_UI_COMPARE_DOM_BENCH_ITERATIONS` and
`INCR_TEA_UI_COMPARE_DOM_BENCH_SAMPLES` to change the sampling budget.
