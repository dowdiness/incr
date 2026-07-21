///|
/// An immutable worksheet snapshot captured by the adapter boundary.
pub struct AdapterCellSnapshot {
  priv id : @typed_spreadsheet.CellId
  priv present : Bool
  priv kind : @typed_spreadsheet.CellKind?
  priv result : @typed_spreadsheet.CellResult
}

///|
pub fn AdapterCellSnapshot::id(
  self : AdapterCellSnapshot,
) -> @typed_spreadsheet.CellId {
  self.id
}

///|
pub fn AdapterCellSnapshot::present(self : AdapterCellSnapshot) -> Bool {
  self.present
}

///|
pub fn AdapterCellSnapshot::kind(
  self : AdapterCellSnapshot,
) -> @typed_spreadsheet.CellKind? {
  self.kind
}

///|
pub fn AdapterCellSnapshot::result(
  self : AdapterCellSnapshot,
) -> @typed_spreadsheet.CellResult {
  self.result
}

///|
fn AdapterCellSnapshot::from_worksheet(
  snapshot : @typed_spreadsheet.CellSnapshot,
) -> AdapterCellSnapshot {
  {
    id: snapshot.id,
    present: snapshot.present,
    kind: snapshot.kind,
    result: snapshot.result,
  }
}

///|
/// An immutable before/after pair for one captured cell.
pub struct AdapterCellSnapshotChange {
  priv id : @typed_spreadsheet.CellId
  priv before : AdapterCellSnapshot
  priv after : AdapterCellSnapshot
}

///|
pub fn AdapterCellSnapshotChange::id(
  self : AdapterCellSnapshotChange,
) -> @typed_spreadsheet.CellId {
  self.id
}

///|
pub fn AdapterCellSnapshotChange::before(
  self : AdapterCellSnapshotChange,
) -> AdapterCellSnapshot {
  self.before
}

///|
pub fn AdapterCellSnapshotChange::after(
  self : AdapterCellSnapshotChange,
) -> AdapterCellSnapshot {
  self.after
}

///|
/// An immutable bounded trace copied from the private worksheet.
pub struct AdapterTrace {
  priv recomputed : ReadOnlyArray[@typed_spreadsheet.CellId]
  priv changed : ReadOnlyArray[@typed_spreadsheet.CellId]
  priv unchanged : ReadOnlyArray[@typed_spreadsheet.CellId]
}

///|
pub fn AdapterTrace::recomputed(
  self : AdapterTrace,
) -> ReadOnlyArray[@typed_spreadsheet.CellId] {
  self.recomputed
}

///|
pub fn AdapterTrace::changed(
  self : AdapterTrace,
) -> ReadOnlyArray[@typed_spreadsheet.CellId] {
  self.changed
}

///|
pub fn AdapterTrace::unchanged(
  self : AdapterTrace,
) -> ReadOnlyArray[@typed_spreadsheet.CellId] {
  self.unchanged
}

///|
fn AdapterTrace::from_worksheet(
  trace : @typed_spreadsheet.WorksheetTrace,
) -> AdapterTrace {
  {
    recomputed: ReadOnlyArray::from_array(trace.recomputed.copy()),
    changed: ReadOnlyArray::from_array(trace.changed.copy()),
    unchanged: ReadOnlyArray::from_array(trace.unchanged.copy()),
  }
}

///|
/// The result of one observed application command.
pub struct ObservedApplyResult {
  priv result : AdapterApplyResult
  priv target : @typed_spreadsheet.CellId?
  priv trace : AdapterTrace?
  priv snapshots : ReadOnlyArray[AdapterCellSnapshotChange]
}

///|
pub fn ObservedApplyResult::result(
  self : ObservedApplyResult,
) -> AdapterApplyResult {
  self.result
}

///|
pub fn ObservedApplyResult::target(
  self : ObservedApplyResult,
) -> @typed_spreadsheet.CellId? {
  self.target
}

///|
pub fn ObservedApplyResult::trace(self : ObservedApplyResult) -> AdapterTrace? {
  self.trace
}

///|
pub fn ObservedApplyResult::snapshots(
  self : ObservedApplyResult,
) -> ReadOnlyArray[AdapterCellSnapshotChange] {
  self.snapshots
}

///|
fn snapshot_cells(
  adapter : EgwAdapter,
  ids : ReadOnlyArray[@typed_spreadsheet.CellId],
) -> ReadOnlyArray[AdapterCellSnapshot] {
  ids.map(id => {
    AdapterCellSnapshot::from_worksheet(adapter.worksheet.inspect_cell(id))
  })
}

///|
fn append_unique_id(
  ids : Array[@typed_spreadsheet.CellId],
  id : @typed_spreadsheet.CellId,
) -> Unit {
  if !ids.contains(id) {
    ids.push(id)
  }
}

///|
fn observed_target(
  command : @domain.SheetCommand,
) -> @typed_spreadsheet.CellId? {
  match command {
    @domain.SheetCommand::ApplyFromSelection(id, _, _)
    | @domain.SheetCommand::ApplyFromEditor(id, _, _)
    | @domain.SheetCommand::DeleteFromSelection(id, _) => Some(id)
    @domain.SheetCommand::ResetDocument(_) => None
  }
}

///|
/// Applies a command through EGW while capturing a bounded worksheet trace.
/// Reset bypasses tracing because it swaps and disposes the worksheet.
pub fn EgwAdapter::apply_command_observed(
  self : EgwAdapter,
  command : @domain.SheetCommand,
  context : @domain.SheetExecutionContext,
  capture? : Array[@typed_spreadsheet.CellId] = [],
  trace_cells? : Array[@typed_spreadsheet.CellId] = [],
) -> ObservedApplyResult raise @container.DocumentError {
  let target = observed_target(command)
  match command {
    @domain.SheetCommand::ResetDocument(_) =>
      {
        result: self.apply_command(command, context),
        target,
        trace: None,
        snapshots: ReadOnlyArray::from_array([]),
      }
    _ => {
      let capture_ids = capture.copy()
      match target {
        Some(id) => append_unique_id(capture_ids, id)
        None => ()
      }
      let observed_ids = capture_ids.copy()
      for id in trace_cells {
        append_unique_id(observed_ids, id)
      }
      let owned_capture = ReadOnlyArray::from_array(capture_ids)
      let before = snapshot_cells(self, owned_capture)
      let command_result : Ref[
        Result[AdapterApplyResult, @container.DocumentError]?,
      ] = Ref(None)
      let (_, worksheet_trace) = self.worksheet.trace_observed_formulas(
        observed_ids,
        () => {
          command_result.val = Some(
            try self.apply_command(command, context) |> Ok catch {
              error => Err(error)
            },
          )
        },
      )
      let result = match command_result.val {
        Some(Ok(result)) => result
        Some(Err(error)) => raise error
        None => abort("observed adapter command did not run")
      }
      let after = snapshot_cells(self, owned_capture)
      let snapshots = owned_capture.mapi((index, id) => AdapterCellSnapshotChange::{
        id,
        before: before[index],
        after: after[index],
      })
      {
        result,
        target,
        trace: Some(AdapterTrace::from_worksheet(worksheet_trace)),
        snapshots,
      }
    }
  }
}

///|
/// Disposes the worksheet owned by this adapter.
pub fn EgwAdapter::dispose(self : EgwAdapter) -> Unit {
  self.worksheet.dispose()
}

///|
/// Queries the AST of a formula without exposing the worksheet.
pub fn EgwAdapter::formula_ast(
  self : EgwAdapter,
  address : String,
) -> Result[@typed_spreadsheet.Formula, @typed_spreadsheet.FormulaAstQueryError] {
  self.worksheet.formula_ast(
    @typed_spreadsheet.CellId::of(self.sheet_id, address),
  )
}
