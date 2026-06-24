# Mounted counter adjacent-framework comparison — 2026-06-14

This is the next measured slice after the [UI-shaped adjacent-framework
comparison plan](2026-06-14-ui-shaped-adjacent-framework-comparison.md). The
first slice measured only pure view/VNode construction; this one mounts a real
counter in Chromium and times a displayed-count update plus an unrelated update.

## What is measured

Each system mounts the same minimal counter into a hidden, attached host:

- a displayed `Count: N` text leaf;
- a `+` button that changes the displayed count;
- a `touch unrelated` button that mutates state not read by the displayed view.

The benchmark records:

1. **initial mount** — construct the app/signals/cells and mount into a fresh
   hidden host; host creation/removal is outside the timing window;
2. **displayed-count click** — click the `+` button and include the framework's
   DOM update/flush work;
3. **unrelated click** — click the unrelated-state button and include the
   framework's skip/rerender/no-subscriber work.

The page uses an immediate `requestAnimationFrame` shim. Rabbita's public
runtime flushes dirty cells on rAF; the shim keeps this benchmark focused on
operation + scheduled flush work rather than browser frame-wait latency. This is
the same boundary as the existing keyed DOM benchmark: hidden attached host,
operation plus flush, samples × iterations. It is not a paint benchmark.

## Implementation notes

- `incr_tea`: `examples/incr_tea/ui_compare_dom_bench.mbt` lives in the root
  package so it can use the package-private `Html`, `Program`, and DOM diff
  helpers while keeping `Html : Eq` closure-free. The click dispatches through a
  real DOM listener, then the harness calls the same direct flush path used by
  the keyed DOM benchmark.
- Rabbita: `examples/incr_tea/browser_ui_compare_bench/` uses public
  `@rabbita.simple_cell`, `@rabbita.new`, and `App::mount`. The unrelated field
  is part of the model but not rendered; changing it still dirties the cell and
  exercises Rabbita's rerender + VDOM diff path.
- Luna: the same JS-only package uses `@luna.signal`, `@luna_dom.text_dyn`, and
  `@luna_dom.render_to`. The unrelated signal has no subscribers, so the click
  exercises Luna's no-subscriber signal update path.

Rabbita and Luna remain isolated to JS-only benchmark package(s). The root
`examples/incr_tea` package still has no `supported_targets = "js"` setting, so
its wasm-gc bench/test surface remains available.

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

| operation | `incr_tea` | Rabbita | Luna |
|---|---:|---:|---:|
| initial mount | 31.7 ± 19.2 | 38.5 ± 15.0 | 15.4 ± 5.02 |
| displayed-count update | 15.1 ± 7.13 | 19.1 ± 9.37 | 5.78 ± 1.00 |
| unrelated update | 6.17 ± 1.35 | 18.1 ± 8.24 | 4.00 ± 0.94 |

## Interpretation

1. **The browser-mounted counter keeps Luna's direct-leaf advantage visible.**
   Luna's displayed-count update is ~2.6× faster than `incr_tea` in this small
   leaf-only workload. That is evidence to keep direct leaf patching (#254) on
   the research list, not evidence to implement it before list/editor-shaped
   browser measurements.
2. **`incr_tea` skips the unrelated view work that Rabbita still pays at the
   dirty-cell boundary.** The unrelated update is ~3× faster than Rabbita here
   because the watched `@incr` view verifies that its dependencies are unchanged
   and the `Html : Eq` root is skipped. Rabbita correctly avoids visible DOM
   changes, but the cell is dirty and its view/diff path still runs.
3. **Luna's unrelated update is the cheapest because the signal has no
   subscribers.** This is the fine-grained no-subscriber case; it does not answer
   hidden-panel activation, keyed list identity, or editor-shaped subtree costs.
4. **Initial mount is not the deciding slice.** All three are tens of
   microseconds in this tiny counter. Larger mounted list/grid/editor slices are
   still needed before prioritizing #254 direct leaf patching, #255 activation
   islands, or #256 WebComponent boundaries.

## Reproduction

```bash
NEW_MOON_MOD=0 moon update
NEW_MOON_MOD=0 moon check --deny-warn -p examples/incr_tea --target js
cd examples/incr_tea
npm install
npm run bench:ui-compare-dom
```

Set `INCR_TEA_UI_COMPARE_DOM_BENCH_ITERATIONS` and
`INCR_TEA_UI_COMPARE_DOM_BENCH_SAMPLES` to change the sampling budget.

## Local API references verified

- `.mooncakes/moonbit-community/rabbita/README.mbt.md`
- `.mooncakes/moonbit-community/rabbita/html/README.mbt.md`
- `.mooncakes/moonbit-community/rabbita/internal/runtime/README.mbt.md`
- `.mooncakes/moonbit-community/rabbita/tea.mbt`
- `.mooncakes/mizchi/luna/src/README.md`
- `.mooncakes/mizchi/luna/src/top.mbt`
- `.mooncakes/mizchi/luna/src/dom/render.mbt`
- `.mooncakes/mizchi/luna/src/examples/hello_luna/main.mbt`
- `.mooncakes/mizchi/luna/src/_bench/dom_bench.mbt`

## Raw samples

<details><summary>Raw JSON</summary>

```json
[
  {
    "system": "incr_tea",
    "operation": "initial-mount",
    "iterations": 200,
    "unit": "us",
    "samples": [
      70,
      48.99999996647239,
      37.5,
      33.49999997764826,
      34.99999998137355,
      12.500000074505806,
      14.000000022351742,
      17.000000048428774,
      16.499999947845936
    ]
  },
  {
    "system": "incr_tea",
    "operation": "displayed-count",
    "iterations": 200,
    "unit": "us",
    "samples": [
      24.00000000372529,
      23.49999999627471,
      20,
      13.500000014901161,
      21.500000022351742,
      8.00000000745058,
      8.500000014901161,
      7.5,
      9.00000000372529
    ]
  },
  {
    "system": "incr_tea",
    "operation": "unrelated",
    "iterations": 200,
    "unit": "us",
    "samples": [
      6.999999992549419,
      9.49999999254942,
      5.499999988824129,
      5.499999988824129,
      5.499999988824129,
      5.500000007450581,
      5.99999999627471,
      5.500000007450581,
      5.499999988824129
    ]
  },
  {
    "system": "rabbita",
    "operation": "initial-mount",
    "iterations": 200,
    "unit": "us",
    "samples": [
      64.49999999254942,
      52.999999932944775,
      47.500000074505806,
      32.99999997019768,
      24.00000000372529,
      33.50000003352761,
      30.999999977648258,
      43.49999997764826,
      16.49999998509884
    ]
  },
  {
    "system": "rabbita",
    "operation": "displayed-count",
    "iterations": 200,
    "unit": "us",
    "samples": [
      20.99999999627471,
      16.50000000372529,
      37.5,
      12.500000018626451,
      10.50000000745058,
      10.499999988824129,
      11.000000014901161,
      25.50000000745058,
      26.50000000372529
    ]
  },
  {
    "system": "rabbita",
    "operation": "unrelated",
    "iterations": 200,
    "unit": "us",
    "samples": [
      25.49999998882413,
      25.99999999627471,
      25.99999999627471,
      28.99999998509884,
      10.499999988824129,
      10.499999988824129,
      10.99999999627471,
      10.50000000745058,
      13.500000014901161
    ]
  },
  {
    "system": "luna",
    "operation": "initial-mount",
    "iterations": 200,
    "unit": "us",
    "samples": [
      23.000000026077032,
      21.999999936670065,
      19.00000000372529,
      12.999999970197678,
      16.000000033527613,
      14.500000029802322,
      10.50000000745058,
      11.499999966472387,
      8.999999985098839
    ]
  },
  {
    "system": "luna",
    "operation": "displayed-count",
    "iterations": 200,
    "unit": "us",
    "samples": [
      6.50000000372529,
      6.999999992549419,
      7.5,
      5.500000007450581,
      5.500000007450581,
      5,
      4.500000011175871,
      5.500000007450581,
      5
    ]
  },
  {
    "system": "luna",
    "operation": "unrelated",
    "iterations": 200,
    "unit": "us",
    "samples": [
      5.99999999627471,
      4.00000000372529,
      3.4999999962747097,
      3.4999999962747097,
      4.00000000372529,
      4.00000000372529,
      2.4999999813735485,
      4.499999992549419,
      4.00000000372529
    ]
  }
]
```

</details>
