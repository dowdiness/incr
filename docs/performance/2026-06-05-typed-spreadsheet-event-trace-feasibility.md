# Typed Spreadsheet Event Trace Feasibility

**Date:** 2026-06-05

**Issue:** [#199](https://github.com/dowdiness/incr/issues/199)

**Status:** Do not replace the bounded snapshot-diff trace path.

## Question

Issue #199 asked whether `Runtime::on_derived_event` could classify
`Worksheet::trace_observed_formulas` results more directly than the current
before/after revision snapshots.

The answer is: technically feasible, but not worth implementing now.

## Baseline rerun

Required guardrail commands were rerun from
[`2026-06-05-typed-spreadsheet-trace-benches.md`](2026-06-05-typed-spreadsheet-trace-benches.md):

```bash
moon bench --release -p examples/typed_spreadsheet -f trace_bench_wbtest.mbt
moon bench --release --target js -p examples/typed_spreadsheet -f trace_bench_wbtest.mbt
```

The 2,500-formula / 100-observed rows stayed inside the existing
sub-millisecond guardrail:

| Scenario | wasm-gc | JS |
|---|---:|---:|
| Bounded one affected | 119.68 µs ± 1.05 µs | 143.56 µs ± 1.47 µs |
| Bounded shared source | 193.14 µs ± 4.18 µs | 267.13 µs ± 32.78 µs |

## Event spike

A temporary white-box spike used this shape:

1. copy and filter the caller-provided observed IDs;
2. pre-read observed formula cells, preserving the current lazy baseline
   contract;
3. register a derived-event listener;
4. run the operation;
5. post-read observed formula cells, preserving the current bounded forcing
   behavior;
6. map `DerivedEvent::Completed.cell_id` through
   `Worksheet.logical_cell_by_runtime_cell`;
7. classify in post-formula order, treating formulas that were not formulas in
   the pre-read set as `changed` and OR-ing any changed completion across
   repeated completions.

That proves the private logical/runtime mapping is sufficient for formula value
cells; no worksheet API would need to expose raw `@incr.CellId`s. Metadata-root
`Derived` cells are not in that map, so their events naturally do not classify
as spreadsheet formulas.

Side-by-side spike measurements for 2,500 formulas / 100 observed formulas:

| Scenario | Current snapshot path wasm-gc | Event spike wasm-gc | Current snapshot path JS | Event spike JS |
|---|---:|---:|---:|---:|
| Bounded no-op | 114.07 µs ± 1.13 µs | 80.62 µs ± 1.22 µs | 112.75 µs ± 7.44 µs | 75.41 µs ± 8.33 µs |
| Bounded one affected | 142.77 µs ± 1.99 µs | 102.56 µs ± 3.36 µs | 172.39 µs ± 6.07 µs | 102.37 µs ± 1.56 µs |
| Bounded shared source | 212.23 µs ± 9.17 µs | 304.00 µs ± 8.70 µs | 234.81 µs ± 2.65 µs | 256.79 µs ± 6.77 µs |

The event path saves tens of microseconds when few or no observed formulas
actually recompute, but it regresses the wasm-gc shared-source case and is not a
clear JS win for the shared-source case. All rows remain far below 1 ms either
way.

## API and lifecycle constraints

- `DerivedEvent::Completed` carries enough revision data for the recomputed /
  changed / unchanged buckets after the observed formulas are explicitly read.
- Events do not remove the need for pre/post reads. Skipping the pre-read would
  make previously lazy formulas look recomputed by the trace itself, and
  skipping the post-read would leave observed formulas lazy and unclassified.
- `Runtime::on_derived_event` is single-listener per runtime. A trace-scoped
  listener would overwrite any existing listener and cannot restore it because
  there is no public getter or subscription token. A permanent worksheet-owned
  listener has the same collision problem for other runtime users or multiple
  worksheets.
- Listener registration and clearing are only valid while the runtime is idle,
  so a trace implementation would have extra failure modes the current
  snapshot path avoids.
- The current `Watch`/GC lifecycle stays simpler: `trace_observed_formulas`
  only performs ordinary outside-graph reads through the existing formula slots.

## Reuse check

- `Worksheet::trace_observed_formulas` remains the public bounded trace API and
  already has the correct caller-bounded laziness contract.
- `Runtime::cell_info` remains the right low-level source for the current
  private before/after revision snapshots.
- `Runtime::on_derived_event` is useful for observers and visualization taps,
  but its single-listener contract makes it a poor fit for a nested worksheet
  helper.
- `Worksheet.logical_cell_by_runtime_cell` can translate formula value events
  privately, so no new public worksheet helper is justified by this
  investigation.

## Decision

Keep the snapshot-diff bounded trace path from #196. Do not file an
event-based implementation issue.

Reopen only if a future measured caller needs the same event stream for another
reason, or if the current 100-observed-formula guardrail moves into
millisecond-scale latency after rerunning the documented benchmark workflow.
