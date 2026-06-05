///|
/// Demo operation vocabulary for typed spreadsheet scenarios.
pub(all) enum SheetOp {
  /// Set one cell to a concrete value.
  SetInput(@typed_spreadsheet.CellId, @typed_spreadsheet.CellValue)
  /// Install a hand-built formula AST with an expected result type.
  SetFormulaAst(
    @typed_spreadsheet.CellId,
    @typed_spreadsheet.CellType,
    @typed_spreadsheet.Formula
  )
  /// Delete one cell from the worksheet.
  Delete(@typed_spreadsheet.CellId)
}

///|
/// The operation-specific result returned by a demo step.
pub(all) enum OpOutcome {
  /// Result returned by `Worksheet::set_input`.
  SetInput(@typed_spreadsheet.CellResult)
  /// Installation result returned by `Worksheet::set_formula_ast`.
  SetFormulaAst(Result[Unit, @typed_spreadsheet.WorksheetError])
  /// Result returned by `Worksheet::delete`.
  Delete(@typed_spreadsheet.CellResult)
}

///|
/// Before/after snapshots for one cell captured around a step.
pub struct CellSnapshotChange {
  id : @typed_spreadsheet.CellId
  before : @typed_spreadsheet.CellSnapshot
  after : @typed_spreadsheet.CellSnapshot
}

///|
/// Result of applying one demo worksheet operation.
pub struct WorksheetStepResult {
  operation : SheetOp
  outcome : OpOutcome
  trace : @typed_spreadsheet.WorksheetTrace
  cell_snapshots : Array[CellSnapshotChange]
}

///|
/// Applies one demo operation and returns snapshots plus worksheet trace data.
///
/// `capture` should list scenario-visible cells whose before/after snapshots
/// the demo wants to show. The operation target is always captured. Formula AST
/// references are also captured for `SetFormulaAst`. `trace_cells` extends the
/// bounded trace region without adding before/after snapshot evidence.
///
/// This runner does not batch the operation. Do not wrap `run_op` itself in
/// `Runtime::batch`: trace classification must observe the operation after any
/// batch commit has completed. Use `run_batched_op` when the demo step needs
/// batch commit semantics and trace correctness together.
pub fn run_op(
  sheet : @typed_spreadsheet.Worksheet,
  operation : SheetOp,
  capture? : Array[@typed_spreadsheet.CellId] = [],
  trace_cells? : Array[@typed_spreadsheet.CellId] = [],
) -> WorksheetStepResult {
  run_op_with_apply(sheet, operation, capture, trace_cells, fn() {
    operation.apply(sheet)
  })
}

///|
/// Applies one demo operation inside the worksheet runtime's batch.
///
/// The batch is nested inside bounded trace classification, so the batch commit
/// completes before post-operation formula reads classify recomputed, changed,
/// and unchanged cells. Call this from outside any existing `Runtime::batch`; an
/// outer batch would defer the real commit until after trace classification.
pub fn run_batched_op(
  sheet : @typed_spreadsheet.Worksheet,
  operation : SheetOp,
  capture? : Array[@typed_spreadsheet.CellId] = [],
  trace_cells? : Array[@typed_spreadsheet.CellId] = [],
) -> WorksheetStepResult {
  run_op_with_apply(sheet, operation, capture, trace_cells, fn() {
    let outcome = Ref(None)
    sheet.runtime.batch(fn() { outcome.val = Some(operation.apply(sheet)) })
    match outcome.val {
      Some(result) => result
      None => abort("run_batched_op batch completed without applying operation")
    }
  })
}

///|
fn run_op_with_apply(
  sheet : @typed_spreadsheet.Worksheet,
  operation : SheetOp,
  capture : Array[@typed_spreadsheet.CellId],
  trace_cells : Array[@typed_spreadsheet.CellId],
  apply : () -> OpOutcome,
) -> WorksheetStepResult {
  let snapshot_ids = operation.snapshot_ids()
  append_unique_cells(snapshot_ids, capture)
  let observed_ids = snapshot_ids.copy()
  append_unique_cells(observed_ids, trace_cells)
  let before = snapshot_cells(sheet, snapshot_ids)
  let (outcome, trace) = sheet.trace_observed_formulas(observed_ids, apply)
  let after = snapshot_cells(sheet, snapshot_ids)
  {
    operation,
    outcome,
    trace,
    cell_snapshots: build_snapshot_changes(snapshot_ids, before, after),
  }
}

///|
fn SheetOp::apply(
  self : SheetOp,
  sheet : @typed_spreadsheet.Worksheet,
) -> OpOutcome {
  match self {
    SetInput(id, value) => SetInput(sheet.set_input(id, value))
    SetFormulaAst(id, declared, formula) =>
      SetFormulaAst(sheet.set_formula_ast(id, declared, formula))
    Delete(id) => Delete(sheet.delete(id))
  }
}

///|
fn SheetOp::snapshot_ids(self : SheetOp) -> Array[@typed_spreadsheet.CellId] {
  let ids = []
  match self {
    SetInput(id, _) | Delete(id) => ids.push(id)
    SetFormulaAst(id, _, formula) => {
      ids.push(id)
      append_unique_cells(ids, formula.refs())
    }
  }
  ids
}

///|
fn snapshot_cells(
  sheet : @typed_spreadsheet.Worksheet,
  ids : Array[@typed_spreadsheet.CellId],
) -> Array[@typed_spreadsheet.CellSnapshot] {
  ids.map(id => sheet.inspect_cell(id))
}

///|
fn build_snapshot_changes(
  ids : Array[@typed_spreadsheet.CellId],
  before : Array[@typed_spreadsheet.CellSnapshot],
  after : Array[@typed_spreadsheet.CellSnapshot],
) -> Array[CellSnapshotChange] {
  let changes = []
  for index in 0..<ids.length() {
    changes.push({ id: ids[index], before: before[index], after: after[index] })
  }
  changes
}

///|
fn append_unique_cells(
  target : Array[@typed_spreadsheet.CellId],
  ids : Array[@typed_spreadsheet.CellId],
) -> Unit {
  ids.each(id => append_unique_cell(target, id))
}

///|
fn append_unique_cell(
  target : Array[@typed_spreadsheet.CellId],
  id : @typed_spreadsheet.CellId,
) -> Unit {
  if !target.contains(id) {
    target.push(id)
  }
}
