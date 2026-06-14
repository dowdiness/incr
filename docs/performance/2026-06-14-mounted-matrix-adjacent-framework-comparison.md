# Mounted matrix adjacent-framework comparison — 2026-06-14

This snapshot extends the mounted-counter browser slice into a batch/matrix
harness. One command now runs the existing counter cells plus keyed-list and
hidden/visible panel cells across `incr_tea`, Rabbita, and Luna.

## What is measured

Every cell mounts into a hidden, attached Chromium host. Host creation/removal is
outside update timing except for the explicit counter **initial mount** row.

The matrix covers:

1. **Counter** — the existing mounted counter cells from the prior snapshot:
   initial mount, displayed-count click, and unrelated-state click.
2. **Keyed list** — N=16/64/256, with `prepend`, `remove-first`, and `reverse`.
   The timed window is the operation click plus framework DOM update/flush. A
   reset back to the N-item baseline runs between timed operations and is not
   included in the timing window.
3. **Hidden/visible panel** — `hidden-update` while closed, `open`,
   `visible-update` while open, and `close`. Per-iteration setup/reset clicks
   put the panel into the required starting state and are not included in the
   timed window.

The page keeps the immediate `requestAnimationFrame` shim from the mounted
counter slice so Rabbita measurements include scheduled flush work without
browser frame-wait latency.

## Implementation notes

- `incr_tea`: the root `examples/incr_tea` package installs counter, keyed-list,
  and panel cells through `install_ui_compare_dom_bench_api()`. This keeps the
  benchmark close to the package-private `Program`, `Html`, and DOM renderer
  helpers while preserving closure-free `Html : Eq`.
- Rabbita: the JS-only `browser_ui_compare_bench` package uses
  `@rabbita.simple_cell`/`@rabbita.new`/`App::mount`. The keyed-list slice uses
  Rabbita's documented `Map[String, Html]` keyed-children API.
- Luna: the same JS-only package uses `@luna.signal`, `@luna.create_root_with_dispose`,
  and `@luna_dom.render_to`. The list slice uses `@luna_dom.for_each` over stable
  string ids; the panel slice uses `@luna_dom.show` so hidden detail content is
  disposed while closed.

Rabbita and Luna remain isolated to JS-only benchmark packages. The root
`examples/incr_tea/moon.pkg` still has no `supported_targets = "js"`, so its
wasm-gc bench/test surface remains available.

## Caveats

This is a mounted timing harness, not a semantic identity/focus equivalence
claim:

- `incr_tea` has browser regression tests for keyed DOM identity/focus behavior;
  the adjacent rows here do not assert those invariants.
- Rabbita keyed children are expressed as a `Map[String, Html]`, matching its
  public docs but not an ordered key-array API. The Rabbita `reverse` cell is
  retained as keyed Map dirty/update cost, not ordered reversal equivalence.
- Luna's list uses `for_each` reference/value reconciliation over stable string
  ids, not an explicit business-key VDOM API.
- Focus retention for moved keyed rows remains framework-specific. Do not use
  this table to claim identical focus behavior.

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

### Counter

| operation | `incr_tea` | Rabbita | Luna |
|---|---:|---:|---:|
| initial mount | 27.6 ± 14.9 | 35.3 ± 13.6 | 13.3 ± 4.48 |
| displayed-count update | 15.4 ± 8.85 | 17.3 ± 6.55 | 5.17 ± 1.09 |
| unrelated update | 5.72 ± 0.83 | 16.9 ± 7.98 | 3.83 ± 0.66 |

### Keyed list

| operation | N | `incr_tea` | Rabbita | Luna |
|---|---:|---:|---:|---:|
| prepend | 16 | 43.8 ± 24.1 | 88.2 ± 14.7 | 10.7 ± 2.02 |
| prepend | 64 | 91.5 ± 5.04 | 271 ± 14.5 | 14.6 ± 2.32 |
| prepend | 256 | 313 ± 24.3 | 1032 ± 15.2 | 34.5 ± 3.46 |
| remove-first | 16 | 22.3 ± 3.74 | 73.9 ± 4.16 | 5.44 ± 1.69 |
| remove-first | 64 | 74.9 ± 3.93 | 260 ± 8.55 | 9.39 ± 1.71 |
| remove-first | 256 | 279 ± 6.87 | 1001 ± 51.1 | 29.6 ± 5.44 |
| reverse† | 16 | 21.1 ± 2.30 | 69.5 ± 3.82 | 12.9 ± 2.60 |
| reverse† | 64 | 74.7 ± 5.18 | 254 ± 9.04 | 40.4 ± 2.19 |
| reverse† | 256 | 284 ± 9.98 | 966 ± 87.1 | 174 ± 9.03 |

† Rabbita's public keyed-child API is Map-based; its reverse cell is not an
ordered key-array reversal equivalence.

### Hidden/visible panel

| operation | `incr_tea` | Rabbita | Luna |
|---|---:|---:|---:|
| hidden update while closed | 4.78 ± 2.03 | 10.8 ± 3.38 | 2.50 ± 0.43 |
| open | 11.9 ± 2.76 | 14.4 ± 1.69 | 11.2 ± 2.30 |
| visible update | 6.83 ± 1.37 | 12.6 ± 2.91 | 3.67 ± 1.60 |
| close | 9.00 ± 1.64 | 11.6 ± 2.96 | 9.83 ± 1.68 |

## Interpretation

1. **The matrix harness is now useful as a batch command.** The same
   `npm run bench:ui-compare-dom` command covers 48 mounted cells, so follow-up
   slices can add rows without one-off scripts.
2. **Keyed list timing separates the systems more clearly than the counter.** At
   N=256, `incr_tea` is ~3.3–3.6× faster than Rabbita on the comparable prepend
   and remove-first rows. Luna's direct `for_each` path is another ~1.6–9× faster
   than `incr_tea` depending on operation. That keeps direct DOM/list patching as
   a real research target, but the identity caveats above prevent treating the
   Luna row or Rabbita reverse row as drop-in semantic replacements.
3. **The panel slice shows the hidden-update shape but not a large crisis.** Luna
   is cheapest when the detail signal has no mounted subscriber. `incr_tea` still
   skips the detail read while closed and lands between Luna and Rabbita. The
   costs are single-digit to low-teens microseconds, so this slice alone does not
   justify implementing activation islands before editor-shaped evidence.
4. **Initial counter mount remains noise-level.** The counter mount row is still
   tens of microseconds and should not drive optimization priority.

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
- `examples/incr_tea/ui_compare_dom_bench.mbt`
- `examples/incr_tea/ui_compare_dom_common.mbt`
- `examples/incr_tea/ui_compare_dom_counter_bench.mbt`
- `examples/incr_tea/ui_compare_dom_keyed_list_bench.mbt`
- `examples/incr_tea/ui_compare_dom_panel_bench.mbt`
- `examples/incr_tea/browser_ui_compare_bench/common.mbt`
- `examples/incr_tea/browser_ui_compare_bench/counter_bench.mbt`
- `examples/incr_tea/browser_ui_compare_bench/keyed_list_bench.mbt`
- `examples/incr_tea/browser_ui_compare_bench/panel_bench.mbt`
- `examples/incr_tea/browser_ui_compare_bench/main.mbt`
- `examples/incr_tea/scripts/bench-keyed-dom.mjs`
- `examples/incr_tea/scripts/bench-ui-compare-dom.mjs`
- `.mooncakes/moonbit-community/rabbita/README.mbt.md`
- `.mooncakes/moonbit-community/rabbita/html/README.mbt.md`
- `.mooncakes/moonbit-community/rabbita/html/children.mbt`
- `.mooncakes/moonbit-community/rabbita/internal/runtime/vdom.mbt`
- `.mooncakes/mizchi/luna/src/README.md`
- `.mooncakes/mizchi/luna/src/top.mbt`
- `.mooncakes/mizchi/luna/src/dom/render.mbt`
- `.mooncakes/mizchi/luna/src/dom/reconcile.mbt`

## Raw samples

<details><summary>Raw JSON</summary>

```json
[
  {
    "system": "incr_tea",
    "suite": "counter",
    "operation": "initial-mount",
    "n": 0,
    "iterations": 200,
    "unit": "us",
    "samples": [
      56.49999996647239,
      41.499999947845936,
      31.99999997392297,
      30.49999998882413,
      29.500000029802322,
      10.499999970197678,
      14.500000011175871,
      15.999999959021807,
      16.99999999254942
    ]
  },
  {
    "system": "incr_tea",
    "suite": "counter",
    "operation": "displayed-count",
    "n": 0,
    "iterations": 200,
    "unit": "us",
    "samples": [
      27.99999998882413,
      24.000000022351742,
      20.49999998882413,
      12.5,
      25,
      6.999999992549419,
      7.5000000186264515,
      8.00000000745058,
      6.499999985098839
    ]
  },
  {
    "system": "incr_tea",
    "suite": "counter",
    "operation": "unrelated",
    "n": 0,
    "iterations": 200,
    "unit": "us",
    "samples": [
      6.000000014901161,
      7.5,
      5.500000007450581,
      5.0000000186264515,
      5.99999999627471,
      6.000000014901161,
      5.500000007450581,
      5.499999988824129,
      4.499999973922968
    ]
  },
  {
    "system": "rabbita",
    "suite": "counter",
    "operation": "initial-mount",
    "n": 0,
    "iterations": 200,
    "unit": "us",
    "samples": [
      55.99999997764826,
      48.49999997764826,
      47.000000048428774,
      31.499999966472387,
      19.499999955296516,
      29.50000001117587,
      27.499999962747097,
      41.499999947845936,
      17.000000029802322
    ]
  },
  {
    "system": "rabbita",
    "suite": "counter",
    "operation": "displayed-count",
    "n": 0,
    "iterations": 200,
    "unit": "us",
    "samples": [
      20,
      18.49999999627471,
      27.5,
      12.5,
      10,
      10.99999999627471,
      11.000000014901161,
      20,
      25.49999998882413
    ]
  },
  {
    "system": "rabbita",
    "suite": "counter",
    "operation": "unrelated",
    "n": 0,
    "iterations": 200,
    "unit": "us",
    "samples": [
      23.50000001490116,
      24.00000000372529,
      24.00000000372529,
      29.00000000372529,
      10.50000000745058,
      9.49999999254942,
      10.50000000745058,
      10.499999988824129,
      10.50000000745058
    ]
  },
  {
    "system": "luna",
    "suite": "counter",
    "operation": "initial-mount",
    "n": 0,
    "iterations": 200,
    "unit": "us",
    "samples": [
      22.999999970197678,
      16.00000001490116,
      16.500000022351742,
      11.000000014901161,
      12.5,
      10.000000037252903,
      11.499999985098839,
      9.500000048428774,
      9.499999973922968
    ]
  },
  {
    "system": "luna",
    "suite": "counter",
    "operation": "displayed-count",
    "n": 0,
    "iterations": 200,
    "unit": "us",
    "samples": [
      6.50000000372529,
      5.99999999627471,
      7.000000011175871,
      4.9999999813735485,
      3.9999999850988393,
      5,
      4.500000011175871,
      4.000000022351742,
      4.500000011175871
    ]
  },
  {
    "system": "luna",
    "suite": "counter",
    "operation": "unrelated",
    "n": 0,
    "iterations": 200,
    "unit": "us",
    "samples": [
      3.4999999962747097,
      4.00000000372529,
      5.499999988824129,
      4.00000000372529,
      3.4999999962747097,
      3.4999999962747097,
      3.4999999962747097,
      3.4999999962747097,
      3.4999999962747097
    ]
  },
  {
    "system": "incr_tea",
    "suite": "keyed-list",
    "operation": "prepend",
    "n": 16,
    "iterations": 200,
    "unit": "us",
    "samples": [
      85.50000006332994,
      42.00000002980232,
      84.49999995529652,
      29.499999936670065,
      25.500000044703484,
      41.50000002235174,
      29.999999925494194,
      27.500000037252903,
      28.499999977648258
    ]
  },
  {
    "system": "incr_tea",
    "suite": "keyed-list",
    "operation": "prepend",
    "n": 64,
    "iterations": 200,
    "unit": "us",
    "samples": [
      93.50000010803342,
      84.00000002235174,
      94.49999997392297,
      86.99999989941716,
      84.49999999254942,
      95.50000006332994,
      97.49999966472387,
      92.00000019744039,
      95
    ]
  },
  {
    "system": "incr_tea",
    "suite": "keyed-list",
    "operation": "prepend",
    "n": 256,
    "iterations": 200,
    "unit": "us",
    "samples": [
      351.4999998547137,
      336.5000000782311,
      320.00000001862645,
      308.0000001192093,
      291.4999999664724,
      279.9999999627471,
      286.4999999292195,
      313.0000000074506,
      332.5000000745058
    ]
  },
  {
    "system": "incr_tea",
    "suite": "keyed-list",
    "operation": "remove-first",
    "n": 16,
    "iterations": 200,
    "unit": "us",
    "samples": [
      27.5,
      20.49999998882413,
      18.000000044703484,
      22.99999998882413,
      18.499999959021807,
      25.50000000745058,
      25.50000000745058,
      24.50000001117587,
      17.500000037252903
    ]
  },
  {
    "system": "incr_tea",
    "suite": "keyed-list",
    "operation": "remove-first",
    "n": 64,
    "iterations": 200,
    "unit": "us",
    "samples": [
      76.49999998509884,
      72.5000000745058,
      78.499999884516,
      77.50000009313226,
      75.50000008195639,
      70.00000001862645,
      79.50000001117587,
      76.5000001527369,
      67.99999993294477
    ]
  },
  {
    "system": "incr_tea",
    "suite": "keyed-list",
    "operation": "remove-first",
    "n": 256,
    "iterations": 200,
    "unit": "us",
    "samples": [
      279.5000001601875,
      287.0000000670552,
      276.9999999925494,
      280.49999998882413,
      269.5000000670552,
      279.49999997392297,
      271.0000001452863,
      290.4999999143183,
      274.50000001117587
    ]
  },
  {
    "system": "incr_tea",
    "suite": "keyed-list",
    "operation": "reverse",
    "n": 16,
    "iterations": 200,
    "unit": "us",
    "samples": [
      21.50000000372529,
      19.499999973922968,
      21.000000052154064,
      23.999999910593033,
      25,
      18.999999929219484,
      22.000000029802322,
      20.000000055879354,
      18.000000026077032
    ]
  },
  {
    "system": "incr_tea",
    "suite": "keyed-list",
    "operation": "reverse",
    "n": 64,
    "iterations": 200,
    "unit": "us",
    "samples": [
      74.49999995529652,
      72.49999986961484,
      68.50000008940697,
      75.49999998882413,
      77.99999991431832,
      65.00000001862645,
      78.50000007078052,
      80.00000013038516,
      79.49999995529652
    ]
  },
  {
    "system": "incr_tea",
    "suite": "keyed-list",
    "operation": "reverse",
    "n": 256,
    "iterations": 200,
    "unit": "us",
    "samples": [
      277.0000000298023,
      272.5000000372529,
      282.99999998882413,
      276.49999994784594,
      283.0000002682209,
      285.5000000074506,
      285.4999999515712,
      307.50000024214387,
      285.0000000372529
    ]
  },
  {
    "system": "rabbita",
    "suite": "keyed-list",
    "operation": "prepend",
    "n": 16,
    "iterations": 200,
    "unit": "us",
    "samples": [
      122.49999990686774,
      87.99999980255961,
      90.49999998882413,
      76.99999993667006,
      76.99999995529652,
      85.50000013783574,
      96.99999997392297,
      76.50000000372529,
      80.0000000745058
    ]
  },
  {
    "system": "rabbita",
    "suite": "keyed-list",
    "operation": "prepend",
    "n": 64,
    "iterations": 200,
    "unit": "us",
    "samples": [
      268.5000001639128,
      285.0000001117587,
      265.4999996908009,
      281.50000005960464,
      254.50000032782555,
      289.00000024586916,
      249.99999983236194,
      282.9999999515712,
      258.00000024959445
    ]
  },
  {
    "system": "rabbita",
    "suite": "keyed-list",
    "operation": "prepend",
    "n": 256,
    "iterations": 200,
    "unit": "us",
    "samples": [
      1020.0000000558794,
      1004.5000000298023,
      1026.500000152737,
      1059.5000000484288,
      1036.0000001080334,
      1043.4999999403954,
      1030.0000001117587,
      1033.500000052154,
      1029.999999962747
    ]
  },
  {
    "system": "rabbita",
    "suite": "keyed-list",
    "operation": "remove-first",
    "n": 16,
    "iterations": 200,
    "unit": "us",
    "samples": [
      70.9999999590218,
      73.499999884516,
      72.99999997019768,
      80.0000000372529,
      66.49999996647239,
      75.50000004470348,
      70.99999997764826,
      77.5000000745058,
      77.50000011175871
    ]
  },
  {
    "system": "rabbita",
    "suite": "keyed-list",
    "operation": "remove-first",
    "n": 64,
    "iterations": 200,
    "unit": "us",
    "samples": [
      261.9999999925494,
      264.9999998882413,
      248.99999985471368,
      267.00000001117587,
      262.50000001862645,
      275.99999990314245,
      255.99999990314242,
      251.50000004097816,
      254.0000000782311
    ]
  },
  {
    "system": "rabbita",
    "suite": "keyed-list",
    "operation": "remove-first",
    "n": 256,
    "iterations": 200,
    "unit": "us",
    "samples": [
      1040.000000037253,
      961.0000001080334,
      962.9999999888241,
      961.000000089407,
      970.4999999888241,
      971.4999999664724,
      1077.5000000186265,
      983.9999999664724,
      1083.500000052154
    ]
  },
  {
    "system": "rabbita",
    "suite": "keyed-list",
    "operation": "reverse",
    "n": 16,
    "iterations": 200,
    "unit": "us",
    "samples": [
      66.49999992921948,
      77.50000014901161,
      68.4999999590218,
      73.49999997764826,
      67.4999999627471,
      65.49999995157123,
      69.50000001117587,
      66.99999991804361,
      70
    ]
  },
  {
    "system": "rabbita",
    "suite": "keyed-list",
    "operation": "reverse",
    "n": 64,
    "iterations": 200,
    "unit": "us",
    "samples": [
      272.50000009313226,
      248.49999994039536,
      258.0000000447035,
      246.500000115484,
      245.5000001937151,
      258.00000017508864,
      244.4999998435378,
      255.00000003725293,
      259.50000001117587
    ]
  },
  {
    "system": "rabbita",
    "suite": "keyed-list",
    "operation": "reverse",
    "n": 256,
    "iterations": 200,
    "unit": "us",
    "samples": [
      1059.5000000298023,
      1057.500000037253,
      1084.5000000856817,
      1013.9999998174607,
      891.4999999292195,
      885.9999999962747,
      865.0000001490116,
      920.5000000633299,
      911.4999999292195
    ]
  },
  {
    "system": "luna",
    "suite": "keyed-list",
    "operation": "prepend",
    "n": 16,
    "iterations": 200,
    "unit": "us",
    "samples": [
      13.500000014901161,
      13.499999977648258,
      12.5,
      9.500000029802322,
      9.500000048428774,
      8.000000026077032,
      10,
      10.999999977648258,
      9.000000078231096
    ]
  },
  {
    "system": "luna",
    "suite": "keyed-list",
    "operation": "prepend",
    "n": 64,
    "iterations": 200,
    "unit": "us",
    "samples": [
      14.499999973922968,
      13.999999985098839,
      11.000000014901161,
      16.49999998509884,
      15.499999988824129,
      17.999999970197678,
      11.500000040978193,
      16.50000000372529,
      13.999999947845936
    ]
  },
  {
    "system": "luna",
    "suite": "keyed-list",
    "operation": "prepend",
    "n": 256,
    "iterations": 200,
    "unit": "us",
    "samples": [
      35.499999951571226,
      35.99999995902181,
      40,
      34.99999998137355,
      36.99999997392297,
      27.999999970197678,
      31.000000070780516,
      34.50000001117587,
      33.49999999627471
    ]
  },
  {
    "system": "luna",
    "suite": "keyed-list",
    "operation": "remove-first",
    "n": 16,
    "iterations": 200,
    "unit": "us",
    "samples": [
      4.000000040978193,
      5,
      7.999999988824129,
      3.9999999850988393,
      6.499999966472387,
      5.499999988824129,
      4.00000000372529,
      4.000000040978193,
      8.00000000745058
    ]
  },
  {
    "system": "luna",
    "suite": "keyed-list",
    "operation": "remove-first",
    "n": 64,
    "iterations": 200,
    "unit": "us",
    "samples": [
      10.99999999627471,
      8.499999977648258,
      9.499999955296516,
      10.000000018626451,
      7.9999999701976785,
      10,
      7.999999988824129,
      12.5,
      6.999999955296516
    ]
  },
  {
    "system": "luna",
    "suite": "keyed-list",
    "operation": "remove-first",
    "n": 256,
    "iterations": 200,
    "unit": "us",
    "samples": [
      33.00000002607703,
      39.00000004097819,
      26.499999910593033,
      29.50000001117587,
      33.99999996647239,
      32.00000001117587,
      21.99999999254942,
      25.99999999627471,
      24.000000078231096
    ]
  },
  {
    "system": "luna",
    "suite": "keyed-list",
    "operation": "reverse",
    "n": 16,
    "iterations": 200,
    "unit": "us",
    "samples": [
      14.000000022351742,
      12.000000067055225,
      12.500000018626451,
      12.5,
      14.000000059604645,
      8.500000014901161,
      10.000000037252903,
      16.500000022351742,
      15.99999999627471
    ]
  },
  {
    "system": "luna",
    "suite": "keyed-list",
    "operation": "reverse",
    "n": 64,
    "iterations": 200,
    "unit": "us",
    "samples": [
      43.00000008195639,
      38.999999947845936,
      40.500000063329935,
      41.500000078231096,
      40.49999997019768,
      41.00000003352761,
      36.000000052154064,
      43.000000063329935,
      39.00000000372529
    ]
  },
  {
    "system": "luna",
    "suite": "keyed-list",
    "operation": "reverse",
    "n": 256,
    "iterations": 200,
    "unit": "us",
    "samples": [
      169.49999986216426,
      164.50000010430813,
      174.4999999180436,
      179.0000000409782,
      157.99999998882413,
      171.50000002235174,
      176.0000000335276,
      181.50000005960464,
      188.00000000745058
    ]
  },
  {
    "system": "incr_tea",
    "suite": "panel",
    "operation": "hidden-update",
    "n": 0,
    "iterations": 200,
    "unit": "us",
    "samples": [
      6.000000014901161,
      5,
      5,
      4.000000022351742,
      3.9999999850988393,
      3.500000014901161,
      3.0000000074505806,
      9.49999999254942,
      2.999999988824129
    ]
  },
  {
    "system": "incr_tea",
    "suite": "panel",
    "operation": "open",
    "n": 0,
    "iterations": 200,
    "unit": "us",
    "samples": [
      16.50000000372529,
      15,
      14.00000000372529,
      11.000000070780516,
      12.000000011175871,
      9.999999981373549,
      8.00000000745058,
      11.500000022351742,
      9.499999973922968
    ]
  },
  {
    "system": "incr_tea",
    "suite": "panel",
    "operation": "visible-update",
    "n": 0,
    "iterations": 200,
    "unit": "us",
    "samples": [
      9.00000000372529,
      7.5,
      7.5,
      4.499999992549419,
      6.500000022351742,
      5.0000000186264515,
      7.5,
      7.000000011175871,
      6.999999955296516
    ]
  },
  {
    "system": "incr_tea",
    "suite": "panel",
    "operation": "close",
    "n": 0,
    "iterations": 200,
    "unit": "us",
    "samples": [
      9.500000011175871,
      7.9999999701976785,
      6.999999992549419,
      6.499999985098839,
      9.500000029802322,
      8.500000033527613,
      10.499999970197678,
      9.999999981373549,
      11.499999966472387
    ]
  },
  {
    "system": "rabbita",
    "suite": "panel",
    "operation": "hidden-update",
    "n": 0,
    "iterations": 200,
    "unit": "us",
    "samples": [
      12.5,
      10.499999988824129,
      11.50000000372529,
      9.500000011175871,
      8.49999999627471,
      19.00000000372529,
      8.49999999627471,
      9.00000000372529,
      8.500000014901161
    ]
  },
  {
    "system": "rabbita",
    "suite": "panel",
    "operation": "open",
    "n": 0,
    "iterations": 200,
    "unit": "us",
    "samples": [
      16.500000022351742,
      14.999999981373549,
      13.500000014901161,
      14.000000022351742,
      14.49999999254942,
      11.000000014901161,
      13.500000014901161,
      16.49999998509884,
      14.999999981373549
    ]
  },
  {
    "system": "rabbita",
    "suite": "panel",
    "operation": "visible-update",
    "n": 0,
    "iterations": 200,
    "unit": "us",
    "samples": [
      16.00000001490116,
      11.50000000372529,
      9.500000011175871,
      10.999999959021807,
      10.499999988824129,
      10.999999977648258,
      13.499999977648258,
      12.000000011175871,
      18.49999999627471
    ]
  },
  {
    "system": "rabbita",
    "suite": "panel",
    "operation": "close",
    "n": 0,
    "iterations": 200,
    "unit": "us",
    "samples": [
      16.00000001490116,
      9.49999999254942,
      10.50000000745058,
      11.000000033527613,
      11.499999966472387,
      8.999999966472387,
      13.00000000745058,
      7.5,
      15.999999959021807
    ]
  },
  {
    "system": "luna",
    "suite": "panel",
    "operation": "hidden-update",
    "n": 0,
    "iterations": 200,
    "unit": "us",
    "samples": [
      3.0000000074505806,
      2.999999988824129,
      2.5000000186264515,
      1.9999999925494196,
      2.5,
      1.9999999925494196,
      3.0000000074505806,
      2.000000011175871,
      2.5
    ]
  },
  {
    "system": "luna",
    "suite": "panel",
    "operation": "open",
    "n": 0,
    "iterations": 200,
    "unit": "us",
    "samples": [
      15.500000044703484,
      11.999999973922968,
      12.999999988824129,
      7.9999999701976785,
      10,
      8.49999999627471,
      12.000000011175871,
      10.499999988824129,
      10.99999999627471
    ]
  },
  {
    "system": "luna",
    "suite": "panel",
    "operation": "visible-update",
    "n": 0,
    "iterations": 200,
    "unit": "us",
    "samples": [
      3.5000000335276127,
      5.0000000186264515,
      1.5000000037252903,
      3.0000000447034836,
      5.499999932944775,
      1.5000000037252903,
      6.000000033527613,
      3.4999999962747097,
      3.4999999590218067
    ]
  },
  {
    "system": "luna",
    "suite": "panel",
    "operation": "close",
    "n": 0,
    "iterations": 200,
    "unit": "us",
    "samples": [
      11.50000000372529,
      7.4999999813735485,
      8.000000026077032,
      12.999999988824129,
      10,
      10,
      9.00000000372529,
      10,
      9.500000048428774
    ]
  }
]
```

</details>
