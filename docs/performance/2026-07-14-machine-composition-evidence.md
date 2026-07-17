# Machine composition aggregate evidence — 2026-07-14

This snapshot measures the aggregate `Program::stateful_cmd` design from the
completed machine-composition evidence driver.
It does not measure layout or paint and does not authorize the conditional
per-key reactive variant.

## Workload and environment

The browser fixture renders editable keyed rows plus a selected-row inspector.
Each recorded operation edits row 0, dispatches through the pure transition and
aggregate Program, recomputes the `Html` view, and synchronously applies the DOM
patch. The harness records one raw object per edit and validates that the edit
creates, removes, and moves no keyed row nodes.

| | |
|---|---|
| Date | 2026-07-14 |
| Host | AMD Ryzen 7 6800H, 8 vCPU, WSL2, linux x64 |
| MoonBit | moon 0.1.20260703 / moonc v0.10.3+16975d007 |
| Node | v24.14.1 |
| Browser | Chromium 148.0.7778.96 via Playwright |
| Sizes | 64 and 256 live children |
| Sampling | 200 unrecorded warm-ups, then 1,000 edits per run, 3 runs per size |
| Command | `rtk npm --prefix examples/incr_tea run bench:machine-composition` |

The run emitted 6,000 raw per-iteration records. By default the script writes
them to `/tmp/incr-machine-composition-raw.json`; set
`MACHINE_COMPOSITION_RAW_PATH` to retain them elsewhere. The records include
transition, view, DOM-patch, and total timings, call counts, row operation
counts, and property/text mutation attribution.

## Structural results

`rtk npm --prefix examples/incr_tea run test:machine-composition` passed:

- local edit preserved every row DOM node and recorded zero created, removed,
  or moved keyed rows;
- edit mutations were attributed only to semantic row `0` and the inspector;
- reverse reorder preserved every semantic row node, with moves distinguished
  from creation/removal;
- stale and duplicate completions still recomputed the equal view through the
  aggregate Program version field, but attempted zero DOM patches and produced
  zero DOM mutations.

## Timing results

All values are microseconds. The timer has roughly 100 µs granularity in this
headless environment, so zero component medians mean “below observable timer
resolution,” not zero work.

| children | run | total p50 | total p95 | transition p95 | view p95 | DOM patch p95 |
|---:|---:|---:|---:|---:|---:|---:|
| 64 | 1 | 100 | 200 | 0 | 100 | 100 |
| 64 | 2 | 0 | 200 | 0 | 100 | 100 |
| 64 | 3 | 0 | 100 | 0 | 100 | 100 |
| 256 | 1 | 100 | 400 | 100 | 200 | 200 |
| 256 | 2 | 100 | 400 | 100 | 200 | 200 |
| 256 | 3 | 100 | 300 | 100 | 100 | 200 |

The pre-registered gate requires every 256-child run to have total p95 below
16,700 µs. All three pass; the slowest run is 400 µs and also remains below
the 8,000 µs stretch target. The noisy 64-to-256 ratios are diagnostic only and
do not alter the absolute gate.

## Decision

The aggregate design meets the structural and synchronous JS-side timing
targets. No per-key reactive ownership experiment is authorized. The result
does not claim end-to-end 60 fps because browser layout and paint are outside
the measured interval.

## Reproduction

```bash
rtk moon test incr_tea/machine_composition_wbtest.mbt
rtk npm --prefix examples/incr_tea run test:machine-composition
rtk npm --prefix examples/incr_tea run bench:machine-composition
```
