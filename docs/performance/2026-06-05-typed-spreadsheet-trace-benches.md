# Typed Spreadsheet Trace Benchmarks

**Date:** 2026-06-05

**Baselines:** `f7be677` (#195 initial full-sheet vs lower-bound trace baseline) and `fea8e6e` (#196 public bounded trace path)

**Backends:** wasm-gc (default), JS (Node + V8)

**Bench file:** [`examples/typed_spreadsheet/trace_bench_wbtest.mbt`](../../examples/typed_spreadsheet/trace_bench_wbtest.mbt)

**Question:** Does `Worksheet::trace` materially pay for all formula cells when a UI-visible edit only needs a bounded trace region, and what manual guardrail should future bounded-trace changes use?

## Performance gate

Issue #179 identified `Worksheet::trace` as an `O(all formula cells)` operation: it enumerates every present formula, reads all formulas before the operation, runs the operation, reads all formulas again, and diffs `changed_at` / `verified_at` snapshots. There was no prior dated measurement for this exact path, so PR #195 established the baseline before designing a bounded trace API.

Existing mitigations did not remove this cost. Formula cells are lazy, and the Rabbita grid render path has a sparse snapshot cache, but `Worksheet::trace` itself still performs a global formula scan by design.

## Manual regression workflow

Use this workflow as the pre-PR check for changes to:

- `Worksheet::trace`, `Worksheet::trace_observed_formulas`, or trace snapshot/classification helpers;
- typed spreadsheet formula slot lifecycle, read priming, or formula filtering;
- Rabbita demo code that changes which cells are considered observed/cached for trace;
- the trace benchmark fixture itself.

Run both backends manually; do not add noisy benchmark assertions to CI:

```bash
# wasm-gc (default)
moon bench --release -p examples/typed_spreadsheet -f trace_bench_wbtest.mbt

# JS backend
moon bench --release --target js -p examples/typed_spreadsheet -f trace_bench_wbtest.mbt
```

For demo-scale regressions, focus on the 2,500-formula rows with 100 observed formulas:

- `trace bench: bounded one affected in 2500 formulas reads 100 formulas`
- `trace bench: bounded shared source in 2500 formulas reads 100 formulas`

Expected order of magnitude after #196: **sub-millisecond**, roughly **0.1–0.25 ms per traced edit** across wasm-gc and JS. Treat a repeatable move into millisecond-scale latency, or any bounded row that grows with all 2,500 formulas rather than the 100 observed formulas, as a regression to investigate before merging. Rerun once on the same host before calling a marginal result, especially on JS where V8 noise is higher.

When changing the fixture, keep the scale explicit: "2,500 formulas" means 2,500 formula cells plus the source input cell, not a hidden 2N worksheet shape.

If the guardrail fails, stop at measurement. Do not optimize further without a fresh microbenchmark that isolates the newly slow operation.

## Fixture

The benchmark builds warmed `examples/typed_spreadsheet` worksheets with cheap AST formulas. Each fixture keeps total worksheet size close to the named formula scale: N formula cells plus one source input cell.

Scenarios:

- **Global no-op**: one formula depends on the source and the other N-1 formulas are literals; the operation sets the source to the same value. This isolates global scan/snapshot overhead with no invalidation.
- **Global one affected**: one formula depends on the source and the other N-1 formulas are literals; the operation changes the source. Only one formula should change, but current `Worksheet::trace` still scans all formulas.
- **Global shared source**: N formulas all depend on one source; changing the source makes every formula in the sheet relevant.
- **Bounded observed formulas**: the benchmark receives a preselected visible formula set and uses the same read/snapshot/diff logic with only that set. PR #195 established this as a wbtest-only lower bound before a public contract existed; PR #196 routes the same scenario through `Worksheet::trace_observed_formulas`. It measures the cost shape when callers already know the bounded observed region.

Setup and first reads happen before timing. Each measured iteration applies one operation and keeps the returned `WorksheetTrace`.

## Measurements

10 internal iterations per bench; mean ± σ. Values are per traced operation.

The first table is the PR #195 baseline. Its bounded rows were benchmark-only lower-bound rows at capture time; keep them as historical target-shape evidence, not the current public API run. Use the post-#196 rows below as the current guardrail.

| Scenario | Sheet formulas | Traced formulas | wasm-gc | JS (Node/V8) |
|---|---:|---:|---:|---:|
| Global no-op | 100 | all | 87.57 µs ± 1.35 µs | 164.22 µs ± 44.42 µs |
| Global no-op | 1,000 | all | 1.37 ms ± 17.40 µs | 5.59 ms ± 2.18 ms |
| Global no-op | 2,500 | all | 5.28 ms ± 537.73 µs | 8.78 ms ± 2.08 ms |
| Global one affected | 100 | all | 101.79 µs ± 0.90 µs | 128.89 µs ± 1.35 µs |
| Global one affected | 1,000 | all | 1.48 ms ± 33.03 µs | 1.71 ms ± 80.85 µs |
| Global one affected | 2,500 | all | 6.66 ms ± 325.92 µs | 8.08 ms ± 411.67 µs |
| Global shared source | 100 | all | 179.35 µs ± 2.24 µs | 209.12 µs ± 3.67 µs |
| Global shared source | 1,000 | all | 2.40 ms ± 60.76 µs | 3.00 ms ± 154.71 µs |
| Global shared source | 2,500 | all | 10.58 ms ± 291.13 µs | 15.14 ms ± 864.63 µs |
| Bounded one affected | 2,500 | 1 | 1.73 µs ± 8.26 ns | 2.56 µs ± 19.85 ns |
| Bounded one affected | 2,500 | 10 | 8.67 µs ± 52.30 ns | 10.44 µs ± 170.44 ns |
| Bounded one affected | 2,500 | 100 | 91.43 µs ± 0.78 µs | 107.63 µs ± 1.99 µs |
| Bounded shared source | 2,500 | 1 | 1.77 µs ± 9.05 ns | 2.54 µs ± 13.28 ns |
| Bounded shared source | 2,500 | 10 | 13.71 µs ± 49.79 ns | 17.72 µs ± 155.15 ns |
| Bounded shared source | 2,500 | 100 | 186.35 µs ± 4.26 µs | 207.31 µs ± 2.38 µs |

Post-#196 public bounded API reference rows, rerun during the #201 docs update:

| Scenario | Sheet formulas | Observed formulas | wasm-gc | JS (Node/V8) |
|---|---:|---:|---:|---:|
| Bounded one affected | 2,500 | 100 | 123.86 µs ± 1.59 µs | 132.33 µs ± 595.44 ns |
| Bounded shared source | 2,500 | 100 | 185.65 µs ± 2.88 µs | 226.50 µs ± 1.52 µs |

## Interpretation

The full-sheet global trace cost is reproduced and significant at the live demo's 50×50 scale. Even the sparse no-op and one-affected cases reach 5–9 ms at 2,500 formulas, because the trace path scans, reads, and snapshots every formula despite at most one formula changing. The shared-source case reaches 10–15 ms at 2,500 formulas, enough to consume most of a 60 Hz frame budget before rendering work.

The bounded path is orders of magnitude smaller when the visible set is small. Against a 2,500-formula sheet, tracing 100 formulas remains roughly 0.1–0.25 ms depending on backend and invalidation shape; tracing 1–10 formulas stays in the low microseconds. The shared-source bounded rows also show that changing an input with many subscribers does not itself force a global formula read in this pull-derived worksheet shape; the global cost comes from `Worksheet::trace` reading and diffing all formulas.

This confirmed #179 was worth designing. The bounded trace contract preserves lazy `Derived` semantics and makes the caller-provided observed region explicit. It does not add a global Excel-style calc chain to `incr` core.

## Decision / status

PR #195 established that global trace is millisecond-scale at the demo's 50×50 formula scale. PR #196 shipped the bounded observed-formula trace path and kept 100 observed formulas sub-millisecond. Future work should use the regression workflow above instead of broad CI benchmark gates.
