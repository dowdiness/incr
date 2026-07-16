///|
/// Serializable AI/tool context for the editable typed spreadsheet demo.

///|
/// Returns a deterministic, bounded AI/tool context for this editor model.
pub fn Model::ai_context_snapshot(
  self : Model,
  region? : Array[String],
  max_cells? : Int = 64,
) -> @demo.AiContextSnapshot {
  let limit = normalize_ai_context_limit(max_cells)
  let (bounded_region, truncated) = bounded_ai_context_region(
    self, region, limit,
  )
  {
    schema_version: 1,
    selected_cell: self.selected_cell,
    max_cells: limit,
    truncated,
    region: bounded_region,
    cells: bounded_region.map(cell => self.ai_context_cell(cell)),
    latest_trace: self.latest_ai_context_trace(),
    latest_evidence: self.latest_ai_context_evidence(),
  }
}

///|
/// Serializes `Model::ai_context_snapshot` as stable indented JSON.
pub fn Model::ai_context_json(
  self : Model,
  region? : Array[String],
  max_cells? : Int = 64,
) -> String {
  self.ai_context_snapshot(region?, max_cells~).to_json().stringify(indent=2)
}

///|
fn Model::publish_ai_context_cmd(self : Model) -> @rabbita.Cmd {
  let json = self.ai_context_json()
  @rabbita_cmd.custom_cmd(
    fn(_) { js_publish_ai_context_json(json) },
    kind=@rabbita_cmd.after_render,
  )
}

///|
fn Model::publish_ai_context(self : Model) -> Unit {
  js_publish_ai_context_json(self.ai_context_json())
}

///|
fn normalize_ai_context_limit(max_cells : Int) -> Int {
  if max_cells < 1 {
    1
  } else {
    max_cells
  }
}

///|
fn bounded_ai_context_region(
  model : Model,
  requested_region : Array[String]?,
  max_cells : Int,
) -> (Array[String], Bool) {
  let source = match requested_region {
    Some(region) => {
      let cells = [model.selected_cell]
      for cell in region {
        append_unique_cell_text(cells, cell)
      }
      cells
    }
    None => default_ai_context_region(model)
  }
  let bounded : Array[String] = []
  let mut truncated = false
  for cell in source {
    if !bounded.contains(cell) {
      if bounded.length() < max_cells {
        bounded.push(cell)
      } else {
        truncated = true
      }
    }
  }
  (bounded, truncated)
}

///|
fn default_ai_context_region(model : Model) -> Array[String] {
  let cells = [model.selected_cell]
  let observed = model.grid_snapshot_cache.keys().to_array()
  observed.sort()
  for cell in observed {
    append_unique_cell_text(cells, cell)
  }
  cells
}

///|
fn append_unique_cell_text(cells : Array[String], cell : String) -> Unit {
  if !cells.contains(cell) {
    cells.push(cell)
  }
}

///|
fn Model::ai_context_cell(self : Model, cell : String) -> @demo.AiContextCell {
  let id = cell_id(self, cell)
  let snapshot = self.sheet.inspect_cell(id)
  let committed_text = committed_for(self, cell)
  let draft_text = draft_for(self, cell)
  {
    id: cell,
    committed_text,
    draft_text,
    draft_dirty: draft_text != committed_text,
    present: snapshot.present,
    kind: @demo.snapshot_kind(snapshot),
    result: ai_context_result(snapshot),
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
fn Model::ai_context_formula(
  self : Model,
  cell : String,
  snapshot : @typed_spreadsheet.CellSnapshot,
) -> @demo.AiContextFormula? {
  match snapshot.kind {
    Some(Formula) => {
      let text = committed_for(self, cell)
      match self.sheet.formula_ast(snapshot.id) {
        Ok(formula) =>
          Some({
            text,
            ast_status: "ok",
            shape: Some(ai_formula_shape(formula)),
            error: None,
          })
        Err(error) =>
          Some({
            text,
            ast_status: formula_ast_error_status(error),
            shape: None,
            error: Some(repr(error)),
          })
      }
    }
    _ => None
  }
}

///|
fn ai_context_result(
  snapshot : @typed_spreadsheet.CellSnapshot,
) -> @demo.AiContextResult {
  if !snapshot.present {
    {
      status: "missing",
      value: None,
      error: cell_result_error(snapshot.result),
      repr: @demo.format_cell_result(snapshot.result),
    }
  } else {
    match snapshot.result {
      Ok(value) =>
        {
          status: "ok",
          value: Some(ai_context_value(value)),
          error: None,
          repr: @demo.format_cell_result(snapshot.result),
        }
      ParseError(_) => ai_context_error_result("parse_error", snapshot.result)
      TypeError(_) => ai_context_error_result("type_error", snapshot.result)
      RefError(_) => ai_context_error_result("ref_error", snapshot.result)
      CycleError(_) => ai_context_error_result("cycle_error", snapshot.result)
    }
  }
}

///|
fn ai_context_error_result(
  status : String,
  result : @typed_spreadsheet.CellResult,
) -> @demo.AiContextResult {
  {
    status,
    value: None,
    error: cell_result_error(result),
    repr: @demo.format_cell_result(result),
  }
}

///|
fn ai_context_value(
  value : @typed_spreadsheet.CellValue,
) -> @demo.AiContextValue {
  match value {
    Int(number) => { type_name: "Int", value: "\{number}", repr: repr(value) }
    Bool(flag) => { type_name: "Bool", value: "\{flag}", repr: repr(value) }
    Text(text) => { type_name: "Text", value: text, repr: repr(value) }
    Blank => { type_name: "Blank", value: "", repr: repr(value) }
  }
}

///|
fn cell_result_error(result : @typed_spreadsheet.CellResult) -> String? {
  match result {
    Ok(_) => None
    ParseError(message)
    | TypeError(message)
    | RefError(message)
    | CycleError(message) => Some(message)
  }
}

///|
fn ai_formula_shape(formula : @typed_spreadsheet.Formula) -> String {
  match formula {
    Literal(value) => {
      let value_text = repr(value)
      "Literal(\{value_text})"
    }
    Ref(id) => {
      let id_text = @demo.cell_id_to_string(id)
      "Ref(\{id_text})"
    }
    Add(lhs, rhs) => ai_binary_formula_shape("Add", lhs, rhs)
    Mul(lhs, rhs) => ai_binary_formula_shape("Mul", lhs, rhs)
    Eq(lhs, rhs) => ai_binary_formula_shape("Eq", lhs, rhs)
    Gt(lhs, rhs) => ai_binary_formula_shape("Gt", lhs, rhs)
    If(condition, then_formula, else_formula) => {
      let condition_text = ai_formula_shape(condition)
      let then_text = ai_formula_shape(then_formula)
      let else_text = ai_formula_shape(else_formula)
      "If(\{condition_text}, \{then_text}, \{else_text})"
    }
  }
}

///|
fn ai_binary_formula_shape(
  tag : String,
  lhs : @typed_spreadsheet.Formula,
  rhs : @typed_spreadsheet.Formula,
) -> String {
  let left = ai_formula_shape(lhs)
  let right = ai_formula_shape(rhs)
  "\{tag}(\{left}, \{right})"
}

///|
fn formula_ast_error_status(
  error : @typed_spreadsheet.FormulaAstQueryError,
) -> String {
  match error {
    ForeignCellId(_) => "foreign_cell_id"
    MissingCell(_) => "missing_cell"
    DeletedCell(_) => "deleted_cell"
    NotFormula(_) => "not_formula"
    OpaqueFormula(_) => "opaque_formula"
  }
}

///|
fn Model::latest_ai_context_trace(self : Model) -> @demo.AiContextTrace? {
  match self.last_step {
    Some(step) =>
      Some({
        edit: self.last_edit,
        outcome: @demo.format_outcome(step.outcome),
        recomputed: @demo.cell_id_strings(step.trace.recomputed),
        changed: @demo.cell_id_strings(step.trace.changed),
        unchanged: @demo.cell_id_strings(step.trace.unchanged),
      })
    None => None
  }
}

///|
fn Model::latest_ai_context_evidence(self : Model) -> @demo.AiContextEvidence? {
  match self.last_step {
    Some(step) =>
      Some({
        edit: self.last_edit,
        outcome: @demo.format_outcome(step.outcome),
        cells: step.cell_snapshots.map(change => {
          ai_context_evidence_cell(change, step)
        }),
      })
    None => None
  }
}

///|
fn ai_context_evidence_cell(
  change : @demo.CellSnapshotChange,
  step : @demo.WorksheetStepResult,
) -> @demo.AiContextEvidenceCell {
  let before_result = ai_context_result(change.before)
  let after_result = ai_context_result(change.after)
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
extern "js" fn js_publish_ai_context_json(json : String) -> Unit =
  #| function(json) {
  #|   var parsed = JSON.parse(json);
  #|   globalThis.__typedSpreadsheetAIContext = parsed;
  #|   globalThis.typedSpreadsheetAIContext = function() { return JSON.parse(json); };
  #|   globalThis.typedSpreadsheetAIContextJson = function() { return json; };
  #| }
