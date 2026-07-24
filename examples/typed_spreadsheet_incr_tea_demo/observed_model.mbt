///|
fn adapter_cell_ids(
  ids : ReadOnlyArray[@typed_spreadsheet.CellId],
) -> Array[@typed_spreadsheet.CellId] {
  let result = []
  for id in ids {
    result.push(id)
  }
  result
}

///|
fn adapter_cell_id_strings(
  ids : ReadOnlyArray[@typed_spreadsheet.CellId],
) -> Array[String] {
  let result = []
  for id in ids {
    result.push(@demo.cell_id_to_string(id))
  }
  result
}

///|
fn adapter_cell_ids_text(
  ids : ReadOnlyArray[@typed_spreadsheet.CellId],
) -> String {
  @demo.format_cell_ids(adapter_cell_ids(ids))
}

///|
fn trace_data_from(
  observed : @egw_adapter.ObservedApplyResult,
  outcome : String,
) -> TraceData {
  match observed.trace() {
    Some(trace) => {
      let recomputed = adapter_cell_id_strings(trace.recomputed())
      let changed = adapter_cell_id_strings(trace.changed())
      let unchanged = adapter_cell_id_strings(trace.unchanged())
      {
        outcome,
        recomputed,
        changed,
        unchanged,
        recomputed_str: adapter_cell_ids_text(trace.recomputed()),
        changed_str: adapter_cell_ids_text(trace.changed()),
        unchanged_str: adapter_cell_ids_text(trace.unchanged()),
        snapshot_count: observed.snapshots().length(),
      }
    }
    None =>
      {
        outcome,
        recomputed: [],
        changed: [],
        unchanged: [],
        recomputed_str: "[]",
        changed_str: "[]",
        unchanged_str: "[]",
        snapshot_count: 0,
      }
  }
}

///|
fn adapter_snapshot_kind(snapshot : @egw_adapter.AdapterCellSnapshot) -> String {
  if !snapshot.present() {
    "missing"
  } else {
    match snapshot.kind() {
      Some(@typed_spreadsheet.CellKind::Input) => "input"
      Some(@typed_spreadsheet.CellKind::Formula) => "formula"
      None => "unknown"
    }
  }
}

///|
fn adapter_result_status(snapshot : @egw_adapter.AdapterCellSnapshot) -> String {
  if !snapshot.present() {
    "missing"
  } else {
    match snapshot.result() {
      @typed_spreadsheet.CellResult::Ok(_) => "ok"
      @typed_spreadsheet.CellResult::ParseError(_) => "parse_error"
      @typed_spreadsheet.CellResult::TypeError(_) => "type_error"
      @typed_spreadsheet.CellResult::RefError(_) => "ref_error"
      @typed_spreadsheet.CellResult::CycleError(_) => "cycle_error"
    }
  }
}

///|
fn adapter_result_changed(
  before : @egw_adapter.AdapterCellSnapshot,
  after : @egw_adapter.AdapterCellSnapshot,
) -> Bool {
  @demo.format_cell_result(before.result()) !=
  @demo.format_cell_result(after.result()) ||
  before.present() != after.present() ||
  adapter_snapshot_kind(before) != adapter_snapshot_kind(after)
}

///|
fn classify_adapter_evidence(
  operation : @demo.SheetOp,
  trace : @egw_adapter.AdapterTrace,
  change : @egw_adapter.AdapterCellSnapshotChange,
) -> String {
  let target = match operation {
    @demo.SheetOp::SetInput(id, _)
    | @demo.SheetOp::SetFormulaAst(id, _, _)
    | @demo.SheetOp::Delete(id) => id
  }
  let target_changed = if change.id() == target {
    match operation {
      @demo.SheetOp::SetInput(_, _) =>
        adapter_result_changed(change.before(), change.after())
      @demo.SheetOp::SetFormulaAst(_, _, _) | @demo.SheetOp::Delete(_) => true
    }
  } else {
    false
  }
  if trace.changed().contains(change.id()) || target_changed {
    "changed"
  } else if trace.unchanged().contains(change.id()) {
    "unchanged"
  } else if trace.recomputed().contains(change.id()) {
    "recomputed"
  } else {
    "unobserved"
  }
}

///|
fn evidence_cell_data(
  operation : @demo.SheetOp,
  trace : @egw_adapter.AdapterTrace,
  change : @egw_adapter.AdapterCellSnapshotChange,
) -> EvidenceCellData {
  let before = change.before()
  let after = change.after()
  {
    id: @demo.cell_id_to_string(change.id()),
    classification: classify_adapter_evidence(operation, trace, change),
    before_kind: adapter_snapshot_kind(before),
    before_result_status: adapter_result_status(before),
    before_result: @demo.format_cell_result(before.result()),
    after_kind: adapter_snapshot_kind(after),
    after_result_status: adapter_result_status(after),
    after_result: @demo.format_cell_result(after.result()),
  }
}

///|
fn observed_outcome(
  operation : @demo.SheetOp,
  after : @egw_adapter.AdapterCellSnapshot,
) -> String {
  match operation {
    @demo.SheetOp::SetInput(_, _) =>
      @demo.format_outcome(@demo.OpOutcome::SetInput(after.result()))
    @demo.SheetOp::SetFormulaAst(_, _, _) =>
      @demo.format_outcome(@demo.OpOutcome::SetFormulaAst(Ok(())))
    @demo.SheetOp::Delete(_) =>
      @demo.format_outcome(@demo.OpOutcome::Delete(after.result()))
  }
}

///|
fn command_target(command : SheetCommand) -> @typed_spreadsheet.CellId? {
  match command {
    ApplyFromSelection(target, _, _)
    | ApplyFromEditor(target, _, _)
    | DeleteFromSelection(target, _) => Some(target)
    ResetDocument(_) => None
  }
}

///|
fn command_edit_text(command : SheetCommand) -> String? {
  match command {
    ApplyFromSelection(_, text, _) | ApplyFromEditor(_, text, _) =>
      Some(text.trim().to_owned())
    DeleteFromSelection(_, _) => None
    ResetDocument(_) => None
  }
}

///|
fn reset_meta(state : Ref[SheetState]) -> Unit {
  let s = state.val
  let seed_drafts : Array[CellDraft] = [
    { cell: "A1", text: "10" },
    { cell: "B1", text: "=A1 + 1" },
  ]
  s.cells.set(grid_cells())
  s.drafts.set(seed_drafts.copy())
  s.committed.set(seed_drafts)
  s.selected_cell.set("B1")
  s.editing_cell.set(None)
  s.trace.set(None)
  s.evidence.set(None)
  s.last_edit.set("Seed sheet")
  s.status.set(
    "Ready. This incr_tea proof is separate from the live Rabbita demo.",
  )
  s.error.set(None)
}

///|
fn record_observed_edit(
  state : Ref[SheetState],
  command : SheetCommand,
  observed : @egw_adapter.ObservedApplyResult,
  operation : @demo.SheetOp,
) -> Unit {
  let target = match observed.target() {
    Some(target) => target
    None => abort("observed edit did not capture its target")
  }
  let target_change = match
    observed.snapshots().search_by(change => change.id() == target) {
    Some(index) => observed.snapshots()[index]
    None => abort("observed edit did not capture its target snapshot")
  }
  let outcome = observed_outcome(operation, target_change.after())
  let trace = match observed.trace() {
    Some(trace) => trace
    None => abort("observed edit did not capture a trace")
  }
  let cell = @demo.cell_id_to_string(target)
  let edit = match command_edit_text(command) {
    Some(text) => "\{cell} ← \{text}"
    None => "delete \{cell}"
  }
  let s = state.val
  s.trace.set(Some(trace_data_from(observed, outcome)))
  let evidence_cells = []
  for change in observed.snapshots() {
    evidence_cells.push(evidence_cell_data(operation, trace, change))
  }
  s.evidence.set(Some({ edit, outcome, cells: evidence_cells }))
  s.last_edit.set(edit)
  s.status.set("Applied \{edit}: \{outcome}.")
  s.error.set(None)
  s.selected_cell.set(cell)
  s.editing_cell.set(None)
}

///|
fn handle_observed_result(
  state : Ref[SheetState],
  command : SheetCommand,
  observed : @egw_adapter.ObservedApplyResult,
) -> CommandApplicability {
  match observed.result() {
    Rejected(applicability) => applicability
    SourceRejected(error) => {
      let target = match observed.target() {
        Some(target) => target
        None => abort("source rejection without a target")
      }
      let cell = @demo.cell_id_to_string(target)
      let s = state.val
      s.selected_cell.set(cell)
      s.editing_cell.set(None)
      match error {
        EmptyInput => {
          s.drafts.set(
            update_draft(
              s.drafts.peek(),
              cell,
              draft_text_from(s.committed.peek(), cell),
            ),
          )
          s.status.set("Left \{cell} unchanged.")
          s.error.set(None)
        }
        _ => {
          s.error.set(Some(format_parse_error(error)))
          s.status.set("Edit not applied.")
        }
      }
      Applicable
    }
    MutationNotLanded => {
      state.val.status.set("Edit not applied.")
      state.val.error.set(Some("Authoritative edit did not land."))
      Applicable
    }
    ProjectionFailed(error) => {
      state.val.status.set("Edit not applied.")
      state.val.error.set(Some("Projection failed: \{repr(error)}"))
      Applicable
    }
    NoSemanticChange(_) | Applied(_) =>
      match command {
        ResetDocument(_) => {
          reset_meta(state)
          Applicable
        }
        _ => {
          let target = match observed.target() {
            Some(target) => target
            None => abort("applied edit without a target")
          }
          let operation = match command {
            ApplyFromSelection(_, text, _) | ApplyFromEditor(_, text, _) =>
              match @demo.parse_cell_text_op(target, text.trim().to_owned()) {
                Ok(operation) => operation
                Err(error) =>
                  abort("adapter accepted an unparsable edit: \{repr(error)}")
              }
            DeleteFromSelection(_, _) => @demo.SheetOp::Delete(target)
            ResetDocument(_) => abort("reset reached observed edit recording")
          }
          record_observed_edit(state, command, observed, operation)
          Applicable
        }
      }
  }
}

///|
fn append_formula_references(
  capture : Array[@typed_spreadsheet.CellId],
  command : SheetCommand,
) -> Unit {
  match command {
    ApplyFromSelection(target, text, _) | ApplyFromEditor(target, text, _) =>
      match @demo.parse_cell_text_op(target, text.trim().to_owned()) {
        Ok(@demo.SheetOp::SetFormulaAst(_, _, formula)) =>
          for reference in formula.refs() {
            if !capture.contains(reference) {
              capture.push(reference)
            }
          }
        _ => ()
      }
    DeleteFromSelection(_, _) | ResetDocument(_) => ()
  }
}

///|
fn format_authority_error(error : @container.DocumentError) -> String {
  match error {
    @container.DocumentError::CycleDetected => "Authority cycle detected."
    @container.DocumentError::EmptyReplicaId => "Authority replica ID is empty."
    @container.DocumentError::Internal(detail~) =>
      "Authority failed internally: \{detail}"
    @container.DocumentError::ParentNotFound =>
      "Authority parent was not found."
    @container.DocumentError::SyncFailed(_) =>
      "Authority synchronization failed."
    @container.DocumentError::TargetNotFound =>
      "Authority target was not found."
  }
}

///|
/// Publishes only a committed EGW version change from a local command.
fn publish_local_sync_if_changed(
  state : Ref[SheetState],
  before : @container.Version,
) -> Unit {
  let publish = match state.val.publish_sync {
    Some(publish) => publish
    None => return
  }
  let adapter = state.val.adapter
  if adapter.version() == before {
    return
  }
  let exported : Result[@container.SyncMessage, @container.DocumentError] = Ok(
    adapter.export_all(),
  ) catch {
    error => Err(error)
  }
  match exported {
    Ok(message) => {
      let applied_status = state.val.status.peek()
      publish(message)
      state.val.status.set("\{applied_status} Shared update sent.")
    }
    Err(error) => state.val.error.set(Some(format_authority_error(error)))
  }
}

///|
fn execute_adapter_command(
  state : Ref[SheetState],
  command : SheetCommand,
) -> CommandApplicability {
  let capture = match command_target(command) {
    Some(target) => state_capture_cell_ids(state, target)
    None => []
  }
  append_formula_references(capture, command)
  let before_version = state.val.adapter.version()
  let attempted : Result[
    @egw_adapter.ObservedApplyResult,
    @container.DocumentError,
  ] = Ok(
    state.val.adapter.apply_command_observed(
      command,
      sheet_execution_context(state),
      capture~,
      trace_cells=state_visible_cell_ids(state),
    ),
  ) catch {
    error => Err(error)
  }
  match attempted {
    Ok(observed) => {
      let applicability = handle_observed_result(state, command, observed)
      publish_local_sync_if_changed(state, before_version)
      applicability
    }
    Err(error) => {
      state.val.status.set("Edit not applied.")
      state.val.error.set(Some(format_authority_error(error)))
      Applicable
    }
  }
}
