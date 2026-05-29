# Typed Spreadsheet API

The `typed_spreadsheet` package provides a typed, formula-oriented spreadsheet
boundary on top of `incr` cells. It is intentionally small: install inputs and
formulas into `Worksheet`, then read results or inspect dependency metadata.

## Package surface

The package exports:

- `SheetId`, `CellId`
- `CellValue`, `CellType`, `CellResult`, `WorksheetError`
- `CellKind`, `CellSnapshot`
- `Worksheet`, `WorksheetTrace`
- Formula constructors in `Formula`

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

```mbt nocheck
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
moon run examples/typed_spreadsheet_cli_demo
moon run examples/typed_spreadsheet_cli_demo -- --format json
```

The CLI uses `examples/typed_spreadsheet_demo`'s operation runner and prints the
operation outcome, trace buckets, and before/after snapshots for each step. That
same demo package also exposes a tiny text parser for demo cell edits:

- `10` installs `SetInput(target, Int(10))`
- `=A1 + 1` installs an integer addition formula
- `=A1 * 2` installs an integer multiplication formula
- `=if(A1 > 10, 1, 0)` installs an integer conditional formula

The parser is intentionally demo-scoped and is not an Excel-compatible grammar.
