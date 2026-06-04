# Typed Spreadsheet Example

The `examples/typed_spreadsheet` package provides a runtime-checked,
formula-oriented spreadsheet boundary on top of `incr` cells. It is
intentionally small: install inputs and formulas into `Worksheet`, then read
results or inspect dependency metadata.

## Package surface

The package exports:

- `SheetId`, `CellId`
- `CellValue`, `CellType`, `CellResult`, `WorksheetError`
- `CellKind`, `CellSnapshot`
- `Worksheet`, `WorksheetTrace`
- Formula constructors in `Formula`

## `CellSnapshot` dependency fields

`Worksheet::inspect_cell` returns three dependency views because spreadsheet
formulas have both static syntax and dynamic runtime behavior:

- `installed_dependencies` — dependencies declared through
  `Worksheet::set_formula(deps, compute)`. For `set_formula_ast`, this remains
  empty because the AST evaluator discovers active reads at runtime.
- `static_references` — the syntactic reference over-approximation collected
  from a `Formula` AST, including inactive conditional branches.
- `last_dynamic_dependencies` — logical worksheet cells read by the last
  completed snapshot/evaluation of the cell's value. Internal worksheet fields
  such as the target cell's own presence/definition inputs are filtered out;
  present dependencies and missing-reference presence checks are both reported as
  the logical referenced `CellId`.

For example, an `If` formula reports the condition and the active branch in
`last_dynamic_dependencies`, while `static_references` retains both branches.
If a missing reference is read, it still appears in `last_dynamic_dependencies`
so callers can explain why creating that cell can make the formula resolve.

## Runtime formula checking

`examples/typed_spreadsheet` does not statically typecheck formulas when they
are installed. `Worksheet::set_formula` and `Worksheet::set_formula_ast` validate
the worksheet boundary (for example, rejecting foreign cell IDs), then install
the cell definition. Operator argument checks, dependency errors, and declared
result type checks happen when the cell is read.

This means installation can succeed for a formula that later evaluates to
`CellResult::TypeError`, such as `Text("x") + Int(1)` or a formula declared as
`Int` whose compute closure returns `Text`. Treat `declared` as an evaluation
contract, not an install-time proof.

See [ADR 2026-06-02](../../docs/decisions/2026-06-02-typed-spreadsheet-runtime-checking.md)
for the decision record.

## Deleted-cell tombstones and compaction

`Worksheet::delete` marks an address absent by setting a stable per-address
presence anchor to `false`. The worksheet keeps that lightweight anchor even
after compaction so formulas that reference a missing address are invalidated
when the address is recreated.

By default, delete also leaves the heavier cell slot in place. That tombstone
lets recreating the same address reuse the existing definition/value slot and
keeps rollback bookkeeping simple. Long-lived sparse sessions can call
`Worksheet::compact_deleted_cells()` after a successful edit (or after
`Runtime::batch`/`batch_result` returns) to remove those heavyweight slots while
retaining the presence anchors. Compaction refreshes present formulas before
pruning so dependents of deleted cells re-anchor on presence rather than on the
soon-to-be-disposed value slot.

Compaction is a post-commit maintenance operation, not a batch-body edit: reads
inside an open batch see pre-commit values, so call it after the batch has
succeeded or failed. The method returns the number of deleted slots pruned.

See [ADR 2026-06-02](../../docs/decisions/2026-06-02-typed-spreadsheet-tombstone-lifecycle.md)
for the lifecycle decision record.

## `WorksheetTrace`

`WorksheetTrace` is returned from `Worksheet::trace` and tracks recompute outcome
for formula cells as three disjoint buckets:

- `recomputed` — formula cells whose `verified_at` revision advanced
- `changed` — formula cells where `changed_at` also advanced
- `unchanged` — formula cells that reverified (`verified_at` advanced) but did not
  change value

`unchanged` means the formula was reverified but produced the same result value; it
does not imply no evaluation work happened.

Use these buckets to distinguish *work done* from *values that actually changed*.

## `Worksheet::trace`

`Worksheet::trace(op)` runs `op` and returns `(result, trace)`.

- `result` is the return value of `op`.
- `trace` is a `WorksheetTrace` for visible formula changes in that worksheet.

Design note:

- `Worksheet::trace` is a before/after summary, not an event log.
- It classifies formula cells by revision metadata observed before and after
  `op`, after forcing reads.
- Buckets include only formula cells present **after** `op`; deleted formula cells
  are not represented as trace events.
- `trace` does not make `op` atomic. Wrap `op` with `Runtime::batch` or
  `Runtime::batch_result` if you need atomic semantics.

Implementation note:

- The method snapshots formula-cell revision metadata before and after `op` using
  `Runtime::cell_info`.
- It first reads all existing formula cells to refresh stale revisions, then reads
  formula cells again after `op` to classify each cell as recomputed/changed/
  unchanged.

### Signature

```moonbit nocheck
pub fn[T] Worksheet::trace(
  self : Worksheet,
  operation : () -> T,
) -> (T, WorksheetTrace)
```

## Example

```mbt check
///|
test "trace after input update" {
  let rt = @incr.Runtime()
  let sheet = @typed_spreadsheet.Worksheet(rt, @typed_spreadsheet.SheetId(1))
  let a1 = @typed_spreadsheet.CellId(sheet.sheet_id(), "A1")
  let b1 = @typed_spreadsheet.CellId(sheet.sheet_id(), "B1")

  ignore(sheet.set_input(a1, @typed_spreadsheet.CellValue::from_int(1)))
  ignore(
    sheet.set_formula(b1, @typed_spreadsheet.CellType::t_int(), [a1], fn(deps) {
      match deps[0] {
        @typed_spreadsheet.CellValue::Int(value) =>
          @typed_spreadsheet.CellResult::ok(
            @typed_spreadsheet.CellValue::from_int(value + 1),
          )
        _ => @typed_spreadsheet.CellResult::type_error("type mismatch")
      }
    }),
  )

  let (_, trace) = sheet.trace(fn() {
    ignore(sheet.set_input(a1, @typed_spreadsheet.CellValue::from_int(2)))
  })

  inspect(trace.changed.contains(b1), content="true")
  inspect(trace.unchanged.length(), content="0")
}
```

For a complete runnable example set, see
`tests/typed_spreadsheet_test.mbt`.

## CLI demo

Run the fixed five-step demo scenario from the repository root:

```bash
moon run --target native examples/typed_spreadsheet_cli_demo
moon run --target native examples/typed_spreadsheet_cli_demo -- --format json
```

The CLI uses `examples/typed_spreadsheet_demo`'s operation runner and prints the
operation outcome, trace buckets, and before/after snapshots for each step. That
same demo package also exposes a tiny text parser for demo cell edits:

- `10` installs `SetInput(target, Int(10))`
- `=A1 + 1` installs an integer addition formula
- `=A1 * 2` installs an integer multiplication formula
- `=if(A1 > 10, 1, 0)` installs an integer conditional formula

The parser is intentionally demo-scoped and is not an Excel-compatible grammar.

## Web demo

Try the editable browser demo at <https://typed-spreadsheet.pages.dev>, or run it
locally from [`examples/typed_spreadsheet_rabbita_demo/`](../typed_spreadsheet_rabbita_demo/).
It uses this package as the worksheet engine, so user edits, formula evaluation,
dependency tracking, trace buckets, and before/after snapshots stay in MoonBit.
