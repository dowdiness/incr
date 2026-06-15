# Incremental TEA activation-islands measurement — 2026-06-15

This snapshot starts issue #255 with measurement only. It does **not** change
`Watch` ownership, root lifecycle, visibility handling, or renderer activation
semantics.

The new mounted `workspace-island` benchmark extends
`npm run bench:ui-compare-dom` with an editor/sidebar/inspector-shaped subtree.
Each timed operation mutates the same document revision input after the harness
has reset the subtree into one of three current-semantics states:

- **collapsed update** — the editor/sidebar/inspector subtree is absent from the
  rendered view and therefore untracked by the watched view root;
- **hidden mounted update** — the subtree remains in the DOM with hidden /
  aria-hidden attributes and the watched view root still reads it;
- **visible update** — the subtree remains visible and the watched view root
  reads it.

Mode reset work runs before the timed operation. The timed window contains the
click/dispatch plus the framework's flush/update work, matching the existing
mounted matrix harness.

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
operation, mean ± sample standard deviation. The #255 decision gate is the
within-system collapsed vs hidden-mounted/visible comparison; cross-system rows
are included for continuity with the adjacent-framework matrix, not as lifecycle-
identical claims.

## Results

### Existing small panel sanity check

| operation | `incr_tea` | Rabbita | Luna |
|---|---:|---:|---:|
| hidden update while closed | 4.33 ± 0.97 | 11.6 ± 3.37 | 2.28 ± 0.51 |
| open | 13.8 ± 3.58 | 17.5 ± 4.97 | 14.6 ± 2.34 |
| visible update | 7.39 ± 1.43 | 15.6 ± 3.78 | 4.06 ± 1.42 |
| close | 10.00 ± 1.06 | 12.2 ± 2.14 | 18.1 ± 11.6 |

### Editor/sidebar/inspector-shaped workspace island

| operation | N | `incr_tea` | Rabbita | Luna |
|---|---:|---:|---:|---:|
| collapsed update | 64 | 13.6 ± 1.96 | 16.4 ± 2.42 | 2.94 ± 0.73 |
| collapsed update | 256 | 9.11 ± 1.52 | 17.6 ± 3.16 | 2.89 ± 1.17 |
| collapsed update | 512 | 8.06 ± 1.10 | 17.7 ± 3.86 | 2.89 ± 1.11 |
| hidden mounted update | 64 | 104 ± 13.1 | 504 ± 48.4 | 38.3 ± 2.28 |
| hidden mounted update | 256 | 297 ± 25.4 | 2471 ± 99.6 | 158 ± 12.8 |
| hidden mounted update | 512 | 617 ± 22.4 | 6533 ± 466 | 311 ± 7.24 |
| visible update | 64 | 85.9 ± 4.74 | 523 ± 17.8 | 40.4 ± 10.2 |
| visible update | 256 | 323 ± 21.8 | 2771 ± 223 | 149 ± 4.91 |
| visible update | 512 | 613 ± 67.5 | 6802 ± 502 | 334 ± 34.7 |

## Interpretation

1. **Collapsed conditionals are already cheap.** The editor-shaped collapsed
   update is flat for `incr_tea` at roughly 8–14 µs, close to the earlier
   small-panel result. If a product can remove a collapsed subtree from the view,
   issue #255 does not need new activation mechanics for that shape.
2. **DOM-present hidden subtrees are now a real measured cost.** At N=512,
   `incr_tea` hidden-mounted updates cost 617 µs, essentially the same as the
   visible update row and far above the collapsed row. This is the first
   measurement in this track that can justify a narrow activation prototype.
3. **The likely target is DOM-preserving inactivity, not ordinary collapsed UI.**
   Any follow-up should preserve explicit DOM presence while testing whether an
   inactive root can pause watched view reads/flushes and rejoin safely on a
   visible/idle/manual trigger.
4. **No direct-patching conclusion follows from this row.** The benchmark uses
   the existing value-level renderer. `incr_tea-direct` remains benchmark-local
   to row/leaf locality and is not generalized here.

## Reproduction

```bash
NEW_MOON_MOD=0 moon check --deny-warn --target js examples/incr_tea
NEW_MOON_MOD=0 moon check --deny-warn --target js examples/incr_tea/browser_ui_compare_bench
cd examples/incr_tea
npm run bench:ui-compare-dom
```

Set `INCR_TEA_UI_COMPARE_DOM_BENCH_ITERATIONS` and
`INCR_TEA_UI_COMPARE_DOM_BENCH_SAMPLES` to change the sampling budget.
