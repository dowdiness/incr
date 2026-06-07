# Typed Spreadsheet Example

The `examples/typed_spreadsheet` package provides a runtime-checked,
formula-oriented spreadsheet boundary on top of `incr` cells. It is
intentionally small: install inputs and formulas into `Worksheet`, then read
results or inspect dependency metadata.

## Package surface

The package exports:

- `SheetId`, `CellId`
- `CellValue`, `CellType`, `CellResult`, `WorksheetError`
- `FormulaAstQueryError`
- `CellKind`, `CellSnapshot`
- `Worksheet`, `WorksheetTrace`
- Formula constructors in `Formula`
- `FormulaDependencyShape` for dependency-shape inspection

## `CellSnapshot` dependency fields

`Worksheet::inspect_cell` returns dependency metadata because spreadsheet
formulas have both static syntax and dynamic runtime behavior:

- `dependency_shape` — whether a formula is applicative/static, selective, or
  dynamic. Input and missing cells report no dependency shape.

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

For example, an `If` formula is `Selective`: it reports the condition and the
active branch in `last_dynamic_dependencies`, while `static_references` retains
both branches. If a missing reference is read, it still appears in
`last_dynamic_dependencies` so callers can explain why creating that cell can
make the formula resolve.

## Formula dependency shapes

`Formula::dependency_shape()` classifies formulas using the Build Systems à la
Carte vocabulary:

- `Applicative` — dependencies are known before evaluation. `Literal`, `Ref`,
  `Add`, `Mul`, `Eq`, and `Gt` over applicative children are applicative.
- `Selective` — all references are syntactically known, but evaluation chooses
  an active branch at runtime. Current `If` formulas are selective unless a
  future child formula becomes dynamic.
- `Dynamic` — dependencies may be chosen from values read during evaluation.
  The current AST has no dynamic-address constructor; this variant is reserved
  for future formulas such as `INDIRECT`.

This classification is inspection metadata only. The typed spreadsheet still
lowers formulas to ordinary dynamic `Derived` evaluation, and this example is not
yet a benchmark-backed driver for an `Expr[T]` API or public static-derived
surface. The static/applicative derived fast path remains private per
[ADR 2026-06-01](../../docs/decisions/2026-06-01-static-derived-public-surface.md).

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

## Formula AST access

`Worksheet::formula_ast(id)` returns the stored `Formula` AST for a present
AST-backed formula cell. The returned formula is a value snapshot of the current
cell definition; replacing the cell with another AST changes the returned shape,
and replacing it with a closure-backed formula reports `OpaqueFormula`.

```moonbit nocheck
pub fn Worksheet::formula_ast(
  self : Worksheet,
  id : CellId,
) -> Result[Formula, FormulaAstQueryError]
```

Query failures are structured so UI/tool callers can distinguish address state:

- `ForeignCellId(id)` — the cell belongs to another worksheet.
- `MissingCell(id)` — the worksheet has never registered a presence anchor for
  the address.
- `DeletedCell(id)` — the address has a presence anchor and is currently absent;
  compaction keeps this tombstone state.
- `NotFormula(id)` — the address is present but stores an input cell.
- `OpaqueFormula(id)` — the address is present but stores a closure-backed
  formula installed through `Worksheet::set_formula`.

## Semantic no-op edits and force paths

`Worksheet::set_input` uses comparable worksheet facts, so setting the same input
value is a no-op. `Worksheet::set_formula_ast` compares the structural `Formula`
AST, so reinstalling the same AST is also a no-op.

Opaque closure formulas installed with `Worksheet::set_formula` can opt into the
same behavior by supplying `fingerprint`. The worksheet treats the dependency
list, declared result type, and fingerprint as the formula's comparable identity.
When no fingerprint is supplied, `set_formula` force-installs the closure so
callers still have a deliberate revalidation path for opaque formulas. For input
cells, use `Worksheet::force_set_input` to force revalidation even when the value
is equal.

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

`WorksheetTrace` is returned from `Worksheet::trace` and
`Worksheet::trace_observed_formulas` and tracks recompute outcome for formula
cells as three disjoint buckets:

- `recomputed` — formula cells whose `verified_at` revision advanced
- `changed` — formula cells where `changed_at` also advanced
- `unchanged` — formula cells that reverified (`verified_at` advanced) but did not
  change value

`unchanged` means the formula was reverified but produced the same result value; it
does not imply no evaluation work happened. Ordinary semantic no-op edits, such as
setting an input to the value it already has, do not appear in `unchanged`; use a
force path when you deliberately want revalidation work.

Use these buckets to distinguish *work done* from *values that actually changed*.

## Trace APIs

`Worksheet::trace(op)` runs `op` and returns `(result, trace)` for the whole
worksheet. `Worksheet::trace_observed_formulas(ids, op)` uses the same trace
buckets, but limits reads and revision snapshots to caller-provided formula IDs.

- `result` is the return value of `op`.
- `trace` is a `WorksheetTrace` for formula changes in the observed set.

Design note:

- Trace APIs produce before/after summaries, not event logs.
- They classify formula cells by revision metadata observed before and after
  `op`, after forcing reads for the observed formula cells.
- Buckets include only formula cells present **after** `op`; deleted formula cells
  are not represented as trace events.
- `trace` does not make `op` atomic. Wrap `op` with `Runtime::batch` or
  `Runtime::batch_result` if you need atomic semantics.

Global vs bounded behavior:

- `Worksheet::trace` scans all formula cells before and after `op`.
- `Worksheet::trace_observed_formulas` copies `ids`, ignores missing, foreign,
  non-formula, and duplicate IDs, and does not read formulas outside that bounded
  set. IDs that become formula cells during `op` can appear in the trace.

### Signatures

```moonbit nocheck
pub fn[T] Worksheet::trace(
  self : Worksheet,
  operation : () -> T,
) -> (T, WorksheetTrace)

pub fn[T] Worksheet::trace_observed_formulas(
  self : Worksheet,
  observed_ids : Array[CellId],
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

  let (_, trace) = sheet.trace_observed_formulas([b1], fn() {
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
