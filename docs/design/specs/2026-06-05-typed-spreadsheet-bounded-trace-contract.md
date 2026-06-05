# Typed Spreadsheet Bounded Trace Contract

**Date:** 2026-06-05

**Status:** Initial example-local implementation for issue #179 after the benchmark baseline landed in PR #195.

## Performance gate

The baseline in [`docs/performance/2026-06-05-typed-spreadsheet-trace-benches.md`](../../performance/2026-06-05-typed-spreadsheet-trace-benches.md) confirmed the driver before design:

- global `Worksheet::trace` over 2,500 formulas costs roughly 5–15 ms across wasm-gc and JS;
- the bounded lower bound over 100 observed formulas costs roughly 91–207 µs.

The cost comes from the example worksheet boundary scanning and reading every formula cell, not from a missing global calc chain in `incr` core.

After routing the bounded benchmark rows through `Worksheet::trace_observed_formulas`, the 100-formula rows remain sub-millisecond: one affected formula measured 122.36 µs wasm-gc / 142.82 µs JS, and shared source measured 199.67 µs wasm-gc / 235.21 µs JS. The difference from the lower bound is the public contract overhead: copy, duplicate filtering, and formula-cell filtering over the caller-provided set.

## Contract

Keep two trace shapes in the typed spreadsheet example:

1. `Worksheet::trace(op)` is the existing whole-worksheet summary. It scans formula cells before and after `op`, reads every formula present in each phase, and reports formula cells present after `op` whose revision metadata advanced.
2. `Worksheet::trace_observed_formulas(ids, op)` is the bounded UI-facing summary. The caller supplies the observed region as logical spreadsheet `CellId`s. The method copies that list, filters it before and after `op`, reads only listed formula cells, and reports the same `WorksheetTrace` buckets for that bounded set.

For the bounded API:

- the demo operation runner observes its snapshot/capture set plus an optional extra trace region, so UI code can refresh cached visible dependents without adding before/after snapshot evidence for every observed formula;
- missing, foreign, input, and duplicate IDs are ignored;
- an ID that is listed and becomes a formula during `op` can appear as `recomputed` and `changed`;
- deleted formulas are not reported, matching the existing global trace semantics;
- formulas outside the observed set remain lazy and are not read by the trace.

## Non-goals

- Do not add an Excel-style global calculation chain.
- Do not expose `Runtime::cell_info`, internal `@incr.CellId`s, or other engine APIs through the spreadsheet API.
- Do not implement `Expr[T]` or formula-language sugar as part of this issue.
- If a real eager-when-reachable driver appears, continue it through the reachable-derived design track rather than duplicating that work here.

## Reuse check

- `Worksheet::trace` remains the whole-sheet API for demos and tests that need global summaries.
- `WorksheetTrace` keeps the existing `recomputed`, `changed`, and `unchanged` buckets.
- The bounded implementation reuses the existing `read_slot` and `formula_revision_snapshot_with_ids` mechanics proven by the benchmark lower bound.
- The demo runner reuses its existing `snapshot_ids` / `capture` region and adds an optional `trace_cells` extension point for sparse viewport/cache anchors.
- New private helpers are limited to choosing the formula trace scope, filtering caller-provided IDs, classifying already-collected revision snapshots, and translating cached grid keys back to worksheet IDs.
