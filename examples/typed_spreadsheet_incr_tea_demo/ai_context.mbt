///|
/// Returns a deterministic, bounded AI/tool context for the incr_tea editor.
fn SheetState::ai_context_snapshot(
  self : SheetState,
  region? : Array[String],
  max_cells? : Int = 64,
) -> @demo.AiContextSnapshot {
  let limit = if max_cells < 1 { 1 } else { max_cells }
  let source = match region {
    Some(requested) => {
      let cells = [self.selected_cell.peek()]
      for cell in requested {
        append_unique_context_cell(cells, cell)
      }
      cells
    }
    None => self.default_ai_context_region()
  }
  let bounded = []
  let mut truncated = false
  for cell in source {
    if !bounded.contains(cell) {
      if bounded.length() < limit {
        bounded.push(cell)
      } else {
        truncated = true
      }
    }
  }
  {
    schema_version: 1,
    selected_cell: self.selected_cell.peek(),
    max_cells: limit,
    truncated,
    region: bounded,
    cells: bounded.map(cell => self.ai_context_cell(cell)),
    latest_trace: self.latest_ai_context_trace(),
    latest_evidence: self.latest_ai_context_evidence(),
  }
}

///|
/// Serializes the current bounded AI/tool context as stable JSON.
fn SheetState::ai_context_json(
  self : SheetState,
  region? : Array[String],
  max_cells? : Int = 64,
) -> String {
  self.ai_context_snapshot(region?, max_cells~).to_json().stringify(indent=2)
}

///|
fn SheetState::default_ai_context_region(self : SheetState) -> Array[String] {
  let selected = self.selected_cell.peek()
  let cells = [selected]
  let snapshot = self.sheet.inspect_cell(
    cell_id_from_sheet(self.sheet, selected),
  )
  for id in snapshot.static_references {
    append_unique_context_cell(cells, @demo.cell_id_to_string(id))
  }
  match self.trace.peek() {
    Some(trace) => {
      for cell in trace.recomputed {
        append_unique_context_cell(cells, cell)
      }
      for cell in trace.changed {
        append_unique_context_cell(cells, cell)
      }
      for cell in trace.unchanged {
        append_unique_context_cell(cells, cell)
      }
    }
    None => ()
  }
  cells
}

///|
fn append_unique_context_cell(cells : Array[String], cell : String) -> Unit {
  if !cells.contains(cell) {
    cells.push(cell)
  }
}

///|
fn SheetState::ai_context_cell(
  self : SheetState,
  cell : String,
) -> @demo.AiContextCell {
  let snapshot = self.sheet.inspect_cell(cell_id_from_sheet(self.sheet, cell))
  let committed_text = draft_text_from(self.committed.peek(), cell)
  let draft_text = draft_text_from(self.drafts.peek(), cell)
  {
    id: cell,
    committed_text,
    draft_text,
    draft_dirty: draft_text != committed_text,
    present: snapshot.present,
    kind: @demo.snapshot_kind(snapshot),
    result: @demo.ai_context_result(snapshot),
    dependency_shape: @demo.format_dependency_shape(snapshot.dependency_shape),
    installed_dependencies: @demo.cell_id_strings(
      snapshot.installed_dependencies,
    ),
    static_references: @demo.cell_id_strings(snapshot.static_references),
    last_dynamic_dependencies: @demo.cell_id_strings(
      snapshot.last_dynamic_dependencies,
    ),
    formula: self.ai_context_formula(cell, snapshot),
  }
}

///|
fn SheetState::ai_context_formula(
  self : SheetState,
  cell : String,
  snapshot : @typed_spreadsheet.CellSnapshot,
) -> @demo.AiContextFormula? {
  match snapshot.kind {
    Some(Formula) => {
      let text = draft_text_from(self.committed.peek(), cell)
      match self.sheet.formula_ast(snapshot.id) {
        Ok(formula) =>
          Some({
            text,
            ast_status: "ok",
            shape: Some(@demo.ai_formula_shape(formula)),
            error: None,
          })
        Err(error) =>
          Some({
            text,
            ast_status: @demo.formula_ast_error_status(error),
            shape: None,
            error: Some(repr(error)),
          })
      }
    }
    _ => None
  }
}

///|
fn SheetState::latest_ai_context_trace(
  self : SheetState,
) -> @demo.AiContextTrace? {
  match self.trace.peek() {
    Some(trace) =>
      Some({
        edit: self.last_edit.peek(),
        outcome: self.status.peek(),
        recomputed: trace.recomputed,
        changed: trace.changed,
        unchanged: trace.unchanged,
      })
    None => None
  }
}

///|
fn SheetState::latest_ai_context_evidence(
  self : SheetState,
) -> @demo.AiContextEvidence? {
  match self.evidence.peek() {
    Some(evidence) =>
      Some({
        edit: evidence.edit,
        outcome: evidence.outcome,
        cells: evidence.cells.map(evidence_cell_to_ai_context),
      })
    None => None
  }
}

///|
fn evidence_cell_to_ai_context(
  cell : EvidenceCellData,
) -> @demo.AiContextEvidenceCell {
  {
    id: cell.id,
    classification: cell.classification,
    before_kind: cell.before_kind,
    before_result_status: cell.before_result_status,
    before_result: cell.before_result,
    after_kind: cell.after_kind,
    after_result_status: cell.after_result_status,
    after_result: cell.after_result,
  }
}

///|
fn evidence_cell_data(
  change : @demo.CellSnapshotChange,
  step : @demo.WorksheetStepResult,
) -> EvidenceCellData {
  let before_result = @demo.ai_context_result(change.before)
  let after_result = @demo.ai_context_result(change.after)
  {
    id: @demo.cell_id_to_string(change.id),
    classification: @demo.classify_evidence(step, change),
    before_kind: @demo.snapshot_kind(change.before),
    before_result_status: before_result.status,
    before_result: before_result.repr,
    after_kind: @demo.snapshot_kind(change.after),
    after_result_status: after_result.status,
    after_result: after_result.repr,
  }
}

///|
fn publish_ai_context_cmd(state : Ref[SheetState]) -> @tea.Cmd[Msg] {
  @tea.Cmd::after_flush(_ => {
    js_publish_ai_context_json(state.val.ai_context_json())
  })
}

///|
#cfg(target="js")
extern "js" fn js_publish_ai_context_json(json : String) -> Unit =
  #| function(json) {
  #|   var parsed = JSON.parse(json);
  #|   globalThis.__typedSpreadsheetAIContext = parsed;
  #|   globalThis.typedSpreadsheetAIContext = function() { return JSON.parse(json); };
  #|   globalThis.typedSpreadsheetAIContextJson = function() { return json; };
  #| }
