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
} derive(ToJson, Debug)

///|
/// Structured typed value for a successful context cell result.
pub(all) struct AiContextValue {
  type_name : String
  value : String
  repr : String
} derive(ToJson, Debug)

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
} derive(ToJson, Debug)

///|
/// One before/after evidence summary cell.
pub(all) struct AiContextEvidenceCell {
  id : String
  classification : String
  before_kind : String
  before_result_status : String
  before_result : String
  after_kind : String
  after_result_status : String
  after_result : String
} derive(ToJson, Debug)

///|
/// Classifies one before/after cell snapshot using the operation trace.
pub fn classify_evidence(
  step : WorksheetStepResult,
  change : CellSnapshotChange,
) -> String {
  let target = match step.operation {
    SetInput(id, _) => id
    SetFormulaAst(id, _, _) => id
    Delete(id) => id
  }
  let before_result = ai_context_result(change.before)
  let after_result = ai_context_result(change.after)
  let before_after_changed = before_result.repr != after_result.repr ||
    change.before.present != change.after.present ||
    snapshot_kind(change.before) != snapshot_kind(change.after)
  let target_changed = if change.id == target {
    match step.operation {
      SetInput(_, _) => before_after_changed
      SetFormulaAst(_, _, _) | Delete(_) => true
    }
  } else {
    false
  }
  if step.trace.changed.contains(change.id) || target_changed {
    "changed"
  } else if step.trace.unchanged.contains(change.id) {
    "unchanged"
  } else if step.trace.recomputed.contains(change.id) {
    "recomputed"
  } else {
    "unobserved"
  }
}

///|
/// Converts a worksheet snapshot to the bounded AI result representation.
pub fn ai_context_result(
  snapshot : @typed_spreadsheet.CellSnapshot,
) -> AiContextResult {
  if !snapshot.present {
    {
      status: "missing",
      value: None,
      error: cell_result_error(snapshot.result),
      repr: format_cell_result(snapshot.result),
    }
  } else {
    match snapshot.result {
      Ok(value) =>
        {
          status: "ok",
          value: Some(ai_context_value(value)),
          error: None,
          repr: format_cell_result(snapshot.result),
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
pub fn ai_context_value(value : @typed_spreadsheet.CellValue) -> AiContextValue {
  match value {
    Int(number) => { type_name: "Int", value: "\{number}", repr: repr(value) }
    Bool(flag) => { type_name: "Bool", value: "\{flag}", repr: repr(value) }
    Text(text) => { type_name: "Text", value: text, repr: repr(value) }
    Blank => { type_name: "Blank", value: "", repr: repr(value) }
  }
}

///|
/// Returns the underlying error text from a worksheet result.
pub fn cell_result_error(result : @typed_spreadsheet.CellResult) -> String? {
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
pub fn ai_formula_shape(formula : @typed_spreadsheet.Formula) -> String {
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
pub fn formula_ast_error_status(
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
