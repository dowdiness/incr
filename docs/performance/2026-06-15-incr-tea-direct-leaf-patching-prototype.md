# Incremental TEA direct leaf patching prototype — 2026-06-15

This snapshot records the narrow #254 prototype added to the mounted row/leaf
locality benchmark. It keeps the existing `incr_tea` value-level renderer as the
baseline and adds one experimental `incr_tea-direct` row/leaf system.

## Prototype shape

The prototype keeps cacheable `Html` values closure-free and `Eq`-comparable:

- `Html` stores pure direct text ids plus fallback strings.
- `Attribute` stores an optional pure direct-attribute id plus a fallback value.
- The row/leaf direct benchmark creates ordinary `@incr` `Derived[String]`
  leaves for the hot row text, hot row class, and hot nested text leaf.
- Those derived leaves are anchored with `Watch[String]` values owned by the
  same component `Scope`.
- Only the renderer/benchmark boundary stores callbacks that resolve pure ids to
  watched strings. The cached `Html` tree never stores a `Watch`, closure, or DOM
  callback.

The direct benchmark renders the static row/list shape once, collects the direct
text/attribute DOM leaves, and subsequent row/leaf operations flush only those
collected leaves. The existing `incr_tea` system still rebuilds/diffs the
value-level `Html` tree and remains the fallback comparison.

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

## Row/leaf results

| operation | N | `incr_tea` | `incr_tea-direct` | Rabbita | Luna |
|---|---:|---:|---:|---:|---:|
| same-order row text | 16 | 22.9 ± 7.03 | 5.33 ± 0.87 | 103 ± 4.99 | 4.89 ± 0.65 |
| same-order row text | 64 | 47.5 ± 5.12 | 4.83 ± 0.50 | 365 ± 18.0 | 3.06 ± 0.30 |
| same-order row text | 256 | 161 ± 13.9 | 4.72 ± 0.62 | 1770 ± 197 | 3.33 ± 0.79 |
| same-order row class | 16 | 15.9 ± 1.76 | 4.78 ± 0.36 | 96.6 ± 3.04 | 3.28 ± 0.67 |
| same-order row class | 64 | 42.9 ± 2.55 | 4.50 ± 0.61 | 355 ± 7.22 | 3.00 ± 0.50 |
| same-order row class | 256 | 153 ± 4.52 | 4.44 ± 0.39 | 1876 ± 91.2 | 3.28 ± 0.67 |
| hot nested text leaf | 16 | 15.4 ± 2.52 | 5.00 ± 1.39 | 105 ± 9.60 | 3.28 ± 0.79 |
| hot nested text leaf | 64 | 41.9 ± 2.70 | 4.44 ± 0.30 | 364 ± 15.9 | 3.11 ± 0.22 |
| hot nested text leaf | 256 | 152 ± 4.93 | 4.72 ± 0.62 | 1922 ± 268 | 3.22 ± 0.62 |

## Interpretation

1. **The prototype clears the #254 locality target.** At N=256,
   `incr_tea-direct` lands around 4.4–4.7 µs for the row text, row class, and
   hot nested text leaf cells, materially below the existing `incr_tea` path and
   below the <20 µs target.
2. **The direct path is intentionally not a renderer replacement.** It covers one
   static row/leaf shape with collected direct leaves. Structural list edits,
   keyed identity/focus behavior, and ordinary changed `Html` values still use
   the existing renderer/diff path.
3. **The useful Luna idea is leaf subscription locality, not wholesale semantics.**
   Luna remains slightly faster in several cells, but the prototype demonstrates
   the same order of magnitude while preserving pure `Html : Eq` descriptors and
   mount-boundary resolver state.
4. **The baseline path still scales with N.** The existing `incr_tea` row/leaf
   cells remain O(N) because the value-level list is rebuilt and diffed. The
   direct path is flat because it reads and patches only the collected hot leaves.

## Reproduction

```bash
NEW_MOON_MOD=0 moon check --deny-warn --target js examples/incr_tea
NEW_MOON_MOD=0 moon check --deny-warn --target js examples/incr_tea/browser_ui_compare_bench
cd examples/incr_tea
npm run bench:ui-compare-dom
```

Set `INCR_TEA_UI_COMPARE_DOM_BENCH_ITERATIONS` and
`INCR_TEA_UI_COMPARE_DOM_BENCH_SAMPLES` to change the sampling budget.
