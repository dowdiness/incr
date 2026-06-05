# Typed Spreadsheet Trace Benchmarks

**Date:** 2026-06-05

**Commit:** `fc3312b` plus benchmark-only branch changes

**Backends:** wasm-gc (default), JS (Node + V8)

**Bench file:** [`examples/typed_spreadsheet/trace_bench_wbtest.mbt`](../../examples/typed_spreadsheet/trace_bench_wbtest.mbt)

**Question:** Does `Worksheet::trace` materially pay for all formula cells when a UI-visible edit only needs a bounded trace region?

## Performance gate

Issue #179 identifies `Worksheet::trace` as an `O(all formula cells)` operation: it enumerates every present formula, reads all formulas before the operation, runs the operation, reads all formulas again, and diffs `changed_at` / `verified_at` snapshots. There was no prior dated measurement for this exact path, so this benchmark establishes the baseline before designing a bounded trace API.

Existing mitigations do not remove this cost. Formula cells are lazy, and the Rabbita grid render path has a sparse snapshot cache, but `Worksheet::trace` itself still performs a global formula scan by design.

## Fixture

The benchmark builds warmed `examples/typed_spreadsheet` worksheets with cheap AST formulas. Each fixture keeps total worksheet size close to the named formula scale: N formula cells plus one source input cell.

Scenarios:

- **Global no-op**: one formula depends on the source and the other N-1 formulas are literals; the operation sets the source to the same value. This isolates global scan/snapshot overhead with no invalidation.
- **Global one affected**: one formula depends on the source and the other N-1 formulas are literals; the operation changes the source. Only one formula should change, but current `Worksheet::trace` still scans all formulas.
- **Global shared source**: N formulas all depend on one source; changing the source makes every formula in the sheet relevant.
- **Bounded lower bound**: the benchmark receives a preselected visible formula set and uses the same read/snapshot/diff logic with only that set. PR #195 established this with a wbtest-only helper before a public contract existed; the #179 follow-up can route the same scenario through a bounded trace API. It measures the best-case cost shape if callers already know the bounded region.

Setup and first reads happen before timing. Each measured iteration applies one operation and keeps the returned `WorksheetTrace`.

## Measurements

10 internal iterations per bench; mean ± σ. Values are per traced operation.

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

## Interpretation

The current global trace cost is reproduced and significant at the live demo's 50×50 scale. Even the sparse no-op and one-affected cases reach 5–9 ms at 2,500 formulas, because the trace path scans, reads, and snapshots every formula despite at most one formula changing. The shared-source case reaches 10–15 ms at 2,500 formulas, enough to consume most of a 60 Hz frame budget before rendering work.

The bounded lower bound is orders of magnitude smaller when the visible set is small. Against a 2,500-formula sheet, tracing 100 formulas costs 91–207 µs depending on backend and invalidation shape; tracing 1–10 formulas stays in the low microseconds. The shared-source bounded rows also show that changing an input with many subscribers does not itself force a global formula read in this pull-derived worksheet shape; the global cost comes from `Worksheet::trace` reading and diffing all formulas.

This confirms #179 is worth designing. The next step should design a bounded trace contract that preserves lazy `Derived` semantics and makes the caller-provided observed region explicit. It should not add a global Excel-style calc chain to `incr` core.

## Decision

Proceed to a bounded trace design/implementation PR after this benchmark baseline. Keep this PR benchmark-only: it demonstrates the problem and gives the bounded API a measurable target.

## Reproduce

```bash
# wasm-gc (default)
moon bench --release -p examples/typed_spreadsheet -f trace_bench_wbtest.mbt

# JS backend
moon bench --release --target js -p examples/typed_spreadsheet -f trace_bench_wbtest.mbt
```
