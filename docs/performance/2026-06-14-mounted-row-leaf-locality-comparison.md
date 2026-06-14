# Mounted row/leaf locality adjacent-framework comparison — 2026-06-14

This snapshot extends the mounted adjacent-framework matrix with the row/leaf
locality slice called out by the `incr_tea` direction doc. The same
`npm run bench:ui-compare-dom` command now runs the prior counter, keyed-list,
and panel cells plus row/leaf locality cells at N=16/64/256.

## What is measured

Every row/leaf cell mounts into a hidden, attached Chromium host. Host
creation/removal is outside update timing. The row keys and order stay fixed;
each timed operation clicks a button that toggles one hot middle row or nested
leaf, then includes the framework's DOM update/flush work.

The new suite covers:

1. **Same-order keyed-row text update** — one middle keyed row changes its label
   text while the key array and row order stay unchanged.
2. **Same-order row class update** — the same middle row toggles its row class
   while keys/order stay unchanged.
3. **Hot nested text leaf update** — a nested text leaf inside the same middle
   row toggles while the surrounding row/list shape stays unchanged.

The existing keyed-list suite still resets between structural list operations;
the row/leaf suite does not reset between timed local toggles because every click
is already the same local operation in the same mounted tree.

## Implementation notes

- `incr_tea`: the root `examples/incr_tea` package owns the benchmark because
  `Program`, `Html`, and the DOM renderer remain package-private. The new rows
  reuse `DomBenchRoot`, `keyed_ul`, pure `Attribute` values, and fixed
  `on_click` descriptors, preserving closure-free `Html : Eq`.
- Rabbita: the JS-only adjacent package mirrors the same state shape with
  `@rabbita.simple_cell` and its documented `Map[String, Html]` keyed children.
- Luna: the JS-only adjacent package keeps the list/order static and uses
  `dyn_class` / `text_dyn` leaves under `@luna_dom.for_each`, representing the
  direct DOM locality target that #254 would need to beat or adapt.

Rabbita and Luna remain isolated to JS-only benchmark packages. The root
`examples/incr_tea/moon.pkg` still has no `supported_targets = "js"`, so its
wasm-gc test/bench surface remains available.

## Caveats

This is a locality timing harness, not a semantic equivalence claim:

- The row/leaf cells deliberately keep key order unchanged; they do not measure
  move/focus behavior.
- Rabbita's keyed rows still use the public Map-shaped keyed-child API, so order
  semantics remain caveated even though this suite does not reorder rows.
- Luna's numbers are direct dynamic leaf/class updates inside a static list,
  not a value-level `Html : Eq` renderer.
- The suite does not implement #254 direct leaf patching; it only supplies the
  browser evidence for deciding whether to prototype it next.

## Environment

| | |
|---|---|
| Date | 2026-06-14 |
| CPU | AMD Ryzen 7 6800H (WSL2), 8 vCPU |
| Toolchain | moon 0.1.20260608 / moonc v0.10.0+e66899a54 |
| JS runtime | Node v24.14.1 |
| Browser | Chromium 148.0.7778.96 via Playwright 1.60.0 |
| Packages | `moonbit-community/rabbita@0.12.3`, `mizchi/luna@0.23.0` |
| Command | `cd examples/incr_tea && npm run bench:ui-compare-dom` |

Each cell below is 9 samples × 200 operations. Units are microseconds per timed
operation, mean ± sample standard deviation.

## Results

### Row/leaf locality

| operation | N | `incr_tea` | Rabbita | Luna |
|---|---:|---:|---:|---:|
| same-order row text | 16 | 22.9 ± 6.66 | 93.3 ± 3.52 | 3.28 ± 0.57 |
| same-order row text | 64 | 43.1 ± 2.45 | 333 ± 3.17 | 3.17 ± 0.35 |
| same-order row text | 256 | 143 ± 2.21 | 1490 ± 22.0 | 3.17 ± 0.35 |
| same-order row class | 16 | 14.8 ± 1.70 | 93.3 ± 3.32 | 3.50 ± 0.43 |
| same-order row class | 64 | 41.4 ± 4.57 | 338 ± 4.70 | 3.00 ± 0.35 |
| same-order row class | 256 | 142 ± 3.32 | 1542 ± 31.4 | 3.17 ± 0.35 |
| hot nested text leaf | 16 | 14.3 ± 1.46 | 94.4 ± 2.58 | 3.00 ± 0.25 |
| hot nested text leaf | 64 | 40.8 ± 2.39 | 346 ± 4.03 | 3.22 ± 0.26 |
| hot nested text leaf | 256 | 141 ± 3.15 | 1533 ± 19.4 | 4.11 ± 0.22 |

## Interpretation

1. **Same-order row/leaf updates are cheaper than structural list edits for
   `incr_tea`, but still scale with N.** At N=256, local row/leaf updates land
   around 141–143 µs versus the same run's structural prepend/remove-first rows
   around 305/281 µs. The same-order fast path avoids reparenting but still
   rebuilds and diffs a value-level list.
2. **The direct DOM locality gap is now measured at editor-relevant row sizes.**
   Luna stays around 3–4 µs across N because only the hot dynamic leaf/class is
   subscribed. That is stronger evidence for a #254 direct leaf patch prototype
   than the toy counter alone.
3. **Rabbita remains a poor locality baseline for this shape.** At N=256 it is
   around 1.49–1.54 ms for the local row/leaf rows, so the useful comparison for
   direct-patching research is `incr_tea` versus a Luna-style direct leaf path,
   not Rabbita's keyed Map update cost.
4. **Do not infer activation-island priority from this slice.** This benchmark
   measures visible local row/leaf updates. The hidden-panel activation-island
   question still needs larger collapsed editor/sidebar/inspector evidence.

## Reproduction

```bash
NEW_MOON_MOD=0 moon update
NEW_MOON_MOD=0 moon check --deny-warn -p examples/incr_tea --target js
NEW_MOON_MOD=0 moon check --deny-warn -p examples/incr_tea/browser_ui_compare_bench --target js
cd examples/incr_tea
npm install
npm run bench:ui-compare-dom
```

Set `INCR_TEA_UI_COMPARE_DOM_BENCH_ITERATIONS` and
`INCR_TEA_UI_COMPARE_DOM_BENCH_SAMPLES` to change the sampling budget.

## Local API references verified

- `examples/incr_tea/dom_bench.mbt`
- `examples/incr_tea/html.mbt`
- `examples/incr_tea/renderer_js.mbt`
- `examples/incr_tea/ui_compare_dom_bench.mbt`
- `examples/incr_tea/ui_compare_dom_common.mbt`
- `examples/incr_tea/ui_compare_dom_keyed_list_bench.mbt`
- `examples/incr_tea/ui_compare_dom_panel_bench.mbt`
- `examples/incr_tea/ui_compare_dom_row_leaf_bench.mbt`
- `examples/incr_tea/browser_ui_compare_bench/common.mbt`
- `examples/incr_tea/browser_ui_compare_bench/keyed_list_bench.mbt`
- `examples/incr_tea/browser_ui_compare_bench/panel_bench.mbt`
- `examples/incr_tea/browser_ui_compare_bench/row_leaf_bench.mbt`
- `examples/incr_tea/browser_ui_compare_bench/main.mbt`
- `examples/incr_tea/scripts/bench-ui-compare-dom.mjs`
- `.mooncakes/moonbit-community/rabbita/README.mbt.md`
- `.mooncakes/moonbit-community/rabbita/html/README.mbt.md`
- `.mooncakes/mizchi/luna/src/README.md`
- `.mooncakes/mizchi/luna/src/dom/render.mbt`

## Raw samples

<details><summary>Row/leaf raw JSON</summary>

```json
[
  {
    "system": "incr_tea",
    "suite": "row-leaf",
    "operation": "row-text",
    "n": 16,
    "iterations": 200,
    "unit": "us",
    "samples": [
      37.5,
      26.00000001490116,
      22.49999998137355,
      28.00000000745058,
      16.99999999254942,
      18.49999999627471,
      17.5,
      18.49999999627471,
      20.99999999627471
    ]
  },
  {
    "system": "incr_tea",
    "suite": "row-leaf",
    "operation": "row-text",
    "n": 64,
    "iterations": 200,
    "unit": "us",
    "samples": [
      43.50000001490116,
      47.49999998137355,
      43.50000001490116,
      40.99999999627471,
      41.50000000372529,
      43.99999998509884,
      39.00000000372529,
      45,
      43.00000000745058
    ]
  },
  {
    "system": "incr_tea",
    "suite": "row-leaf",
    "operation": "row-text",
    "n": 256,
    "iterations": 200,
    "unit": "us",
    "samples": [
      145.49999998882413,
      140.9999999962747,
      147.00000001117587,
      144.0000000037253,
      142.00000001117587,
      140.9999999962747,
      145,
      141.5000000037253,
      141.99999999254942
    ]
  },
  {
    "system": "incr_tea",
    "suite": "row-leaf",
    "operation": "row-class",
    "n": 16,
    "iterations": 200,
    "unit": "us",
    "samples": [
      13.499999977648258,
      15,
      15,
      14.49999999254942,
      13.500000014901161,
      19.00000000372529,
      13.49999999627471,
      14.49999999254942,
      14.49999999254942
    ]
  },
  {
    "system": "incr_tea",
    "suite": "row-leaf",
    "operation": "row-class",
    "n": 64,
    "iterations": 200,
    "unit": "us",
    "samples": [
      41.99999999254942,
      39.00000000372529,
      39.50000001117587,
      40.49999998882413,
      53.00000000745058,
      36.99999999254942,
      40,
      40.50000000745058,
      41.49999998509884
    ]
  },
  {
    "system": "incr_tea",
    "suite": "row-leaf",
    "operation": "row-class",
    "n": 256,
    "iterations": 200,
    "unit": "us",
    "samples": [
      136.00000001490116,
      142.50000001862645,
      143.4999999962747,
      143.00000000745058,
      142.49999998137355,
      146.5000000037253,
      145.50000000745058,
      141.5000000037253,
      137.99999998882413
    ]
  },
  {
    "system": "incr_tea",
    "suite": "row-leaf",
    "operation": "hot-leaf-text",
    "n": 16,
    "iterations": 200,
    "unit": "us",
    "samples": [
      13.00000000745058,
      16.49999998509884,
      13.500000014901161,
      14.500000011175871,
      13.999999985098839,
      14.00000000372529,
      17.00000001117587,
      13.49999999627471,
      13.00000000745058
    ]
  },
  {
    "system": "incr_tea",
    "suite": "row-leaf",
    "operation": "hot-leaf-text",
    "n": 64,
    "iterations": 200,
    "unit": "us",
    "samples": [
      40.50000000745058,
      40.99999997764826,
      43.50000001490116,
      39.00000000372529,
      39.49999999254942,
      39.00000002235174,
      37.99999998882413,
      41.00000001490116,
      45.50000000745058
    ]
  },
  {
    "system": "incr_tea",
    "suite": "row-leaf",
    "operation": "hot-leaf-text",
    "n": 256,
    "iterations": 200,
    "unit": "us",
    "samples": [
      142.5,
      136.99999999254942,
      141.49999998509884,
      138.50000001490116,
      145,
      137.5,
      142.5,
      145.9999999962747,
      140.9999999962747
    ]
  },
  {
    "system": "rabbita",
    "suite": "row-leaf",
    "operation": "row-text",
    "n": 16,
    "iterations": 200,
    "unit": "us",
    "samples": [
      98.49999999627471,
      94.99999998137355,
      97.99999998882413,
      93.99999998509884,
      90.50000000745058,
      94.49999999254942,
      90.50000000745058,
      89.00000002235174,
      90
    ]
  },
  {
    "system": "rabbita",
    "suite": "row-leaf",
    "operation": "row-text",
    "n": 64,
    "iterations": 200,
    "unit": "us",
    "samples": [
      329.0000000037253,
      335.9999999962747,
      330,
      337.99999998882413,
      333.4999999962747,
      334.0000000037253,
      331.5000000037253,
      330,
      335.9999999962747
    ]
  },
  {
    "system": "rabbita",
    "suite": "row-leaf",
    "operation": "row-text",
    "n": 256,
    "iterations": 200,
    "unit": "us",
    "samples": [
      1521.4999999850988,
      1478.0000000074506,
      1466.9999999925494,
      1478.4999999962747,
      1476.5000000037253,
      1519.0000000037253,
      1515.4999999888241,
      1470,
      1486.5000000037253
    ]
  },
  {
    "system": "rabbita",
    "suite": "row-leaf",
    "operation": "row-class",
    "n": 16,
    "iterations": 200,
    "unit": "us",
    "samples": [
      92.5,
      99.50000001117587,
      90.50000000745058,
      92.5,
      96.50000000372529,
      89.50000001117587,
      90.99999999627471,
      91.50000002235174,
      95.99999999627471
    ]
  },
  {
    "system": "rabbita",
    "suite": "row-leaf",
    "operation": "row-class",
    "n": 64,
    "iterations": 200,
    "unit": "us",
    "samples": [
      345.49999998882413,
      338.50000001490116,
      332.99999998882413,
      339.0000000037253,
      335.9999999962747,
      346.5000000037253,
      336.9999999925494,
      335,
      334.99999998137355
    ]
  },
  {
    "system": "rabbita",
    "suite": "row-leaf",
    "operation": "row-class",
    "n": 256,
    "iterations": 200,
    "unit": "us",
    "samples": [
      1480,
      1502.0000000111759,
      1551.5000000037253,
      1582.9999999888241,
      1560.5000000074506,
      1554.4999999925494,
      1551.9999999925494,
      1548.0000000074506,
      1547.5
    ]
  },
  {
    "system": "rabbita",
    "suite": "row-leaf",
    "operation": "hot-leaf-text",
    "n": 16,
    "iterations": 200,
    "unit": "us",
    "samples": [
      98.00000000745058,
      92.99999998882413,
      95,
      93.49999999627471,
      97.99999998882413,
      91.49999998509884,
      96.50000000372529,
      92.00000001117587,
      92.00000001117587
    ]
  },
  {
    "system": "rabbita",
    "suite": "row-leaf",
    "operation": "hot-leaf-text",
    "n": 64,
    "iterations": 200,
    "unit": "us",
    "samples": [
      342.5,
      351.00000001490116,
      341.9999999925494,
      346.9999999925494,
      352.5,
      345.49999998882413,
      345.9999999962747,
      344.0000000037253,
      340.5000000074506
    ]
  },
  {
    "system": "rabbita",
    "suite": "row-leaf",
    "operation": "hot-leaf-text",
    "n": 256,
    "iterations": 200,
    "unit": "us",
    "samples": [
      1522.5,
      1530.9999999962747,
      1531.9999999925494,
      1499.9999999813735,
      1550,
      1570,
      1520.9999999962747,
      1533.4999999962747,
      1534.0000000037253
    ]
  },
  {
    "system": "luna",
    "suite": "row-leaf",
    "operation": "row-text",
    "n": 16,
    "iterations": 200,
    "unit": "us",
    "samples": [
      3.4999999962747097,
      2.999999988824129,
      3.4999999962747097,
      4.00000000372529,
      3.500000014901161,
      3.4999999962747097,
      3.0000000074505806,
      3.4999999962747097,
      2.000000011175871
    ]
  },
  {
    "system": "luna",
    "suite": "row-leaf",
    "operation": "row-text",
    "n": 64,
    "iterations": 200,
    "unit": "us",
    "samples": [
      3.4999999962747097,
      2.999999988824129,
      3.4999999962747097,
      3.0000000074505806,
      3.0000000074505806,
      2.4999999813735485,
      3.500000014901161,
      3.4999999962747097,
      3.0000000074505806
    ]
  },
  {
    "system": "luna",
    "suite": "row-leaf",
    "operation": "row-text",
    "n": 256,
    "iterations": 200,
    "unit": "us",
    "samples": [
      3.4999999962747097,
      3.500000014901161,
      3.0000000074505806,
      3.4999999962747097,
      3.500000014901161,
      2.999999988824129,
      2.999999988824129,
      3.0000000074505806,
      2.5000000186264515
    ]
  },
  {
    "system": "luna",
    "suite": "row-leaf",
    "operation": "row-class",
    "n": 16,
    "iterations": 200,
    "unit": "us",
    "samples": [
      2.4999999813735485,
      4.00000000372529,
      3.4999999962747097,
      3.4999999962747097,
      4.00000000372529,
      3.500000014901161,
      3.4999999962747097,
      3.500000014901161,
      3.4999999962747097
    ]
  },
  {
    "system": "luna",
    "suite": "row-leaf",
    "operation": "row-class",
    "n": 64,
    "iterations": 200,
    "unit": "us",
    "samples": [
      2.5,
      3.0000000074505806,
      2.999999988824129,
      3.4999999962747097,
      3.4999999962747097,
      2.999999988824129,
      2.5,
      3.0000000074505806,
      3.0000000074505806
    ]
  },
  {
    "system": "luna",
    "suite": "row-leaf",
    "operation": "row-class",
    "n": 256,
    "iterations": 200,
    "unit": "us",
    "samples": [
      2.999999988824129,
      2.999999988824129,
      3.0000000074505806,
      2.999999988824129,
      3.0000000074505806,
      3.9999999850988393,
      3.0000000074505806,
      3.0000000074505806,
      3.4999999962747097
    ]
  },
  {
    "system": "luna",
    "suite": "row-leaf",
    "operation": "hot-leaf-text",
    "n": 16,
    "iterations": 200,
    "unit": "us",
    "samples": [
      2.5,
      3.0000000074505806,
      3.0000000074505806,
      3.0000000074505806,
      3.4999999962747097,
      3.0000000074505806,
      3.0000000074505806,
      3.000000026077032,
      2.999999988824129
    ]
  },
  {
    "system": "luna",
    "suite": "row-leaf",
    "operation": "hot-leaf-text",
    "n": 64,
    "iterations": 200,
    "unit": "us",
    "samples": [
      3.0000000074505806,
      3.4999999962747097,
      2.999999988824129,
      3.500000014901161,
      3.0000000074505806,
      3.500000014901161,
      3.500000014901161,
      3.0000000074505806,
      2.999999988824129
    ]
  },
  {
    "system": "luna",
    "suite": "row-leaf",
    "operation": "hot-leaf-text",
    "n": 256,
    "iterations": 200,
    "unit": "us",
    "samples": [
      4.00000000372529,
      4.00000000372529,
      4.500000011175871,
      3.9999999850988393,
      4.00000000372529,
      4.00000000372529,
      4.500000011175871,
      4.00000000372529,
      4.00000000372529
    ]
  }
]
```

</details>
