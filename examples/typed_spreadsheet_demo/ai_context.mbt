///|
/// Serializable AI/tool context schema shared by spreadsheet renderers.
pub(all) struct AiContextSnapshot {
  schema_version : Int
  selected_cell : String
  max_cells : Int
  truncated : Bool
  region : Array[String]
  cells : Array[AiContextCell]
  latest_trace : AiContextTrace?
  latest_evidence : AiContextEvidence?
} derive(ToJson, Debug)

///|
/// Serializable view of one bounded cell in an AI/tool context snapshot.
pub(all) struct AiContextCell {
  id : String
  committed_text : String
  draft_text : String
  draft_dirty : Bool
  present : Bool
  kind : String
  result : AiContextResult
  dependency_shape : String
  installed_dependencies : Array[String]
  static_references : Array[String]
  last_dynamic_dependencies : Array[String]
  formula : AiContextFormula?
} derive(ToJson, Debug)

///|
/// Structured value or error state for one context cell.
pub(all) struct AiContextResult {
  status : String
  value : AiContextValue?
  error : String?
  repr : String
} derive(ToJson, Debug, Eq)

///|
/// Structured typed value for a successful context cell result.
pub(all) struct AiContextValue {
  type_name : String
  value : String
  repr : String
} derive(ToJson, Debug, Eq)

///|
/// Formula text and AST-backed shape metadata for a formula cell.
pub(all) struct AiContextFormula {
  text : String
  ast_status : String
  shape : String?
  error : String?
} derive(ToJson, Debug)

///|
/// Latest bounded recompute/change trace available from a spreadsheet model.
pub(all) struct AiContextTrace {
  edit : String
  outcome : String
  recomputed : Array[String]
  changed : Array[String]
  unchanged : Array[String]
} derive(ToJson, Debug)

///|
/// Latest bounded before/after evidence summary available from a spreadsheet model.
pub(all) struct AiContextEvidence {
  edit : String
  outcome : String
  cells : Array[AiContextEvidenceCell]
} derive(ToJson, Debug, Eq)

///|
/// One before/after evidence summary cell.
pub(all) struct AiContextEvidenceCell {
  id : String
  classification : String
  before : AiContextResult
  before_kind : String
  before_result_status : String
  before_result : String
  after : AiContextResult
  after_kind : String
  after_result_status : String
  after_result : String
} derive(ToJson, Debug, Eq)

///|
/// Minimal worksheet state needed for shared AI evidence conversion.
pub struct AiContextCellObservation {
  id : @typed_spreadsheet.CellId
  present : Bool
  kind : @typed_spreadsheet.CellKind?
  result : @typed_spreadsheet.CellResult
}

///|
/// Creates an immutable observation at a renderer or adapter boundary.
pub fn AiContextCellObservation::AiContextCellObservation(
  id : @typed_spreadsheet.CellId,
  present : Bool,
  kind : @typed_spreadsheet.CellKind?,
  result : @typed_spreadsheet.CellResult,
) -> AiContextCellObservation {
  { id, present, kind, result }
}

///|
/// Converts a full worksheet snapshot to the shared evidence input.
fn ai_context_cell_observation(
  snapshot : @typed_spreadsheet.CellSnapshot,
) -> AiContextCellObservation {
  AiContextCellObservation(
    snapshot.id,
    snapshot.present,
    snapshot.kind,
    snapshot.result,
  )
}

///|
fn classify_ai_context_evidence(
  operation : SheetOp,
  recomputed : ReadOnlyArray[@typed_spreadsheet.CellId],
  changed : ReadOnlyArray[@typed_spreadsheet.CellId],
  unchanged : ReadOnlyArray[@typed_spreadsheet.CellId],
  before : AiContextCellObservation,
  after : AiContextCellObservation,
) -> String {
  let target = match operation {
    SetInput(id, _) => id
    SetFormulaAst(id, _, _) => id
    Delete(id) => id
  }
  let before_result = ai_context_result_from(before.present, before.result)
  let after_result = ai_context_result_from(after.present, after.result)
  let before_after_changed = before_result.repr != after_result.repr ||
    before.present != after.present ||
    ai_context_kind(before.present, before.kind) !=
    ai_context_kind(after.present, after.kind)
  let target_changed = if after.id == target {
    match operation {
      SetInput(_, _) => before_after_changed
      SetFormulaAst(_, _, _) | Delete(_) => true
    }
  } else {
    false
  }
  if changed.contains(after.id) || target_changed {
    "changed"
  } else if unchanged.contains(after.id) {
    "unchanged"
  } else if recomputed.contains(after.id) {
    "recomputed"
  } else {
    "unobserved"
  }
}

///|
/// Converts one adapter-neutral before/after observation to shared evidence.
pub fn ai_context_evidence_cell(
  operation : SheetOp,
  recomputed : ReadOnlyArray[@typed_spreadsheet.CellId],
  changed : ReadOnlyArray[@typed_spreadsheet.CellId],
  unchanged : ReadOnlyArray[@typed_spreadsheet.CellId],
  before : AiContextCellObservation,
  after : AiContextCellObservation,
) -> AiContextEvidenceCell {
  ai_context_evidence_cell_from_observations(
    classify_ai_context_evidence(
      operation, recomputed, changed, unchanged, before, after,
    ),
    before,
    after,
  )
}

///|
/// Converts classified adapter-neutral observations to shared evidence.
pub fn ai_context_evidence_cell_from_observations(
  classification : String,
  before : AiContextCellObservation,
  after : AiContextCellObservation,
) -> AiContextEvidenceCell {
  let before_result = ai_context_result_from(before.present, before.result)
  let after_result = ai_context_result_from(after.present, after.result)
  {
    id: cell_id_to_string(after.id),
    classification,
    before: before_result,
    before_kind: ai_context_kind(before.present, before.kind),
    before_result_status: before_result.status,
    before_result: before_result.repr,
    after: after_result,
    after_kind: ai_context_kind(after.present, after.kind),
    after_result_status: after_result.status,
    after_result: after_result.repr,
  }
}

///|
/// Converts one worksheet step to paired, bounded trace and evidence schemas.
pub fn worksheet_step_ai_context_history(
  edit : String,
  step : WorksheetStepResult,
  max_items : Int,
) -> (AiContextTrace, AiContextEvidence) {
  let recomputed = ReadOnlyArray::from_array(step.trace.recomputed)
  let changed = ReadOnlyArray::from_array(step.trace.changed)
  let unchanged = ReadOnlyArray::from_array(step.trace.unchanged)
  ai_context_history(
    edit,
    format_outcome(step.outcome),
    cell_id_strings(step.trace.recomputed),
    cell_id_strings(step.trace.changed),
    cell_id_strings(step.trace.unchanged),
    step.cell_snapshots.map(change => {
      ai_context_evidence_cell(
        step.operation,
        recomputed,
        changed,
        unchanged,
        ai_context_cell_observation(change.before),
        ai_context_cell_observation(change.after),
      )
    }),
    max_items,
  )
}

///|
/// Converts a worksheet snapshot to the bounded AI result representation.
fn ai_context_result(
  snapshot : @typed_spreadsheet.CellSnapshot,
) -> AiContextResult {
  ai_context_result_from(snapshot.present, snapshot.result)
}

///|
fn ai_context_result_from(
  present : Bool,
  result : @typed_spreadsheet.CellResult,
) -> AiContextResult {
  if !present {
    {
      status: "missing",
      value: None,
      error: cell_result_error(result),
      repr: format_cell_result(result),
    }
  } else {
    match result {
      Ok(value) =>
        {
          status: "ok",
          value: Some(ai_context_value(value)),
          error: None,
          repr: format_cell_result(result),
        }
      ParseError(_) => ai_context_error_result("parse_error", result)
      TypeError(_) => ai_context_error_result("type_error", result)
      RefError(_) => ai_context_error_result("ref_error", result)
      CycleError(_) => ai_context_error_result("cycle_error", result)
    }
  }
}

///|
fn ai_context_error_result(
  status : String,
  result : @typed_spreadsheet.CellResult,
) -> AiContextResult {
  {
    status,
    value: None,
    error: cell_result_error(result),
    repr: format_cell_result(result),
  }
}

///|
/// Converts a typed worksheet value to the AI context value representation.
fn ai_context_value(value : @typed_spreadsheet.CellValue) -> AiContextValue {
  match value {
    Int(number) => { type_name: "Int", value: "\{number}", repr: repr(value) }
    Bool(flag) => { type_name: "Bool", value: "\{flag}", repr: repr(value) }
    Text(text) => { type_name: "Text", value: text, repr: repr(value) }
    Blank => { type_name: "Blank", value: "", repr: repr(value) }
  }
}

///|
/// Returns the underlying error text from a worksheet result.
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
/// Converts a formula AST to a compact, deterministic shape string.
fn ai_formula_shape(formula : @typed_spreadsheet.Formula) -> String {
  match formula {
    Literal(value) => "Literal(\{repr(value)})"
    Ref(id) => "Ref(\{cell_id_to_string(id)})"
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
  "\{tag}(\{ai_formula_shape(lhs)}, \{ai_formula_shape(rhs)})"
}

///|
/// Converts a formula AST query error to a stable status string.
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
/// Converts formula text and an AST query outcome to shared formula metadata.
fn ai_context_formula(
  text : String,
  ast : Result[
    @typed_spreadsheet.Formula,
    @typed_spreadsheet.FormulaAstQueryError,
  ],
) -> AiContextFormula {
  match ast {
    Ok(formula) =>
      {
        text,
        ast_status: "ok",
        shape: Some(ai_formula_shape(formula)),
        error: None,
      }
    Err(error) =>
      {
        text,
        ast_status: formula_ast_error_status(error),
        shape: None,
        error: Some(repr(error)),
      }
  }
}

///|
/// Converts assembled worksheet cell state to the shared cell schema.
/// `formula_ast` is present only when `snapshot` describes a formula cell.
pub fn ai_context_cell(
  id : String,
  committed_text : String,
  draft_text : String,
  snapshot : @typed_spreadsheet.CellSnapshot,
  formula_ast : Result[
    @typed_spreadsheet.Formula,
    @typed_spreadsheet.FormulaAstQueryError,
  ]?,
) -> AiContextCell {
  let formula = match formula_ast {
    Some(ast) => Some(ai_context_formula(committed_text, ast))
    None => None
  }
  {
    id,
    committed_text,
    draft_text,
    draft_dirty: draft_text != committed_text,
    present: snapshot.present,
    kind: snapshot_kind(snapshot),
    result: ai_context_result(snapshot),
    dependency_shape: format_dependency_shape(snapshot.dependency_shape),
    installed_dependencies: cell_id_strings(snapshot.installed_dependencies),
    static_references: cell_id_strings(snapshot.static_references),
    last_dynamic_dependencies: cell_id_strings(
      snapshot.last_dynamic_dependencies,
    ),
    formula,
  }
}

///|
/// Converts renderer history fields to paired, bounded trace and evidence.
pub fn ai_context_history(
  edit : String,
  outcome : String,
  recomputed : Array[String],
  changed : Array[String],
  unchanged : Array[String],
  evidence_cells : Array[AiContextEvidenceCell],
  max_items : Int,
) -> (AiContextTrace, AiContextEvidence) {
  (
    ai_context_trace(edit, outcome, recomputed, changed, unchanged, max_items),
    ai_context_evidence(edit, outcome, evidence_cells, max_items),
  )
}

///|
fn ai_context_trace(
  edit : String,
  outcome : String,
  recomputed : Array[String],
  changed : Array[String],
  unchanged : Array[String],
  max_items : Int,
) -> AiContextTrace {
  {
    edit,
    outcome,
    recomputed: bounded_ai_context_items(recomputed, max_items),
    changed: bounded_ai_context_items(changed, max_items),
    unchanged: bounded_ai_context_items(unchanged, max_items),
  }
}

///|
fn ai_context_evidence(
  edit : String,
  outcome : String,
  cells : Array[AiContextEvidenceCell],
  max_items : Int,
) -> AiContextEvidence {
  { edit, outcome, cells: bounded_ai_context_items(cells, max_items) }
}

///|
fn[T] bounded_ai_context_items(items : Array[T], max_items : Int) -> Array[T] {
  let limit = if max_items < 1 { 1 } else { max_items }
  items[:items.length().min(limit)].to_owned()
}

///|
/// Bounds an ordered region while always retaining the selected cell first.
pub fn bounded_ai_context_region(
  selected_cell : String,
  source : Array[String],
  max_cells : Int,
) -> (Int, Array[String], Bool) {
  let limit = if max_cells < 1 { 1 } else { max_cells }
  let bounded = []
  let mut truncated = false
  for cell in [selected_cell, ..source] {
    if !bounded.contains(cell) {
      if bounded.length() < limit {
        bounded.push(cell)
      } else {
        truncated = true
      }
    }
  }
  (limit, bounded, truncated)
}

///|
fn ai_context_kind(
  present : Bool,
  kind : @typed_spreadsheet.CellKind?,
) -> String {
  if !present {
    "missing"
  } else {
    match kind {
      Some(Input) => "input"
      Some(Formula) => "formula"
      None => "unknown"
    }
  }
}
