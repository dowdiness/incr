///|
/// A deterministic explanation query failed before producing an answer.
pub(all) enum ExplanationQueryError {
  CellOutsideObservedRegion(String)
} derive(ToJson, Debug, Eq)

///|
/// The bounded region in which an explanation answer is complete.
pub struct ExplanationScope {
  max_cells : Int
  truncated : Bool
  region : ReadOnlyArray[String]
} derive(ToJson, Debug)

///|
/// One formula input resolved within or outside the observed region.
pub struct ExplanationInput {
  id : String
  observed : Bool
  result : AiContextResult?
} derive(ToJson, Debug)

///|
/// Bounded engine activity retained as secondary diagnostic evidence.
pub struct ExplanationTrace {
  recomputed : ReadOnlyArray[String]
  changed : ReadOnlyArray[String]
  unchanged : ReadOnlyArray[String]
} derive(ToJson, Debug)

///|
/// Selected-cell evidence normalized for human and tool consumers.
pub struct ExplanationEvidence {
  classification : String
  before_status : String
  before_result : String
  after_status : String
  after_result : String
} derive(ToJson, Debug, Eq)

///|
/// Deterministic before/after facts for the latest bounded edit.
pub struct LastChangeAnswer {
  schema_version : Int
  subject : String
  scope : ExplanationScope
  edit : String
  outcome : String
  evidence : ExplanationEvidence?
  trace : ExplanationTrace
} derive(ToJson, Debug)

///|
/// Deterministic semantic facts explaining one observed spreadsheet cell.
pub struct ExplainCellAnswer {
  schema_version : Int
  subject : String
  scope : ExplanationScope
  present : Bool
  kind : String
  result : AiContextResult
  formula : AiContextFormula?
  active_inputs : ReadOnlyArray[ExplanationInput]
  inactive_inputs : ReadOnlyArray[ExplanationInput]
} derive(ToJson, Debug)

///|
/// Explains one cell using only deterministic facts from a bounded snapshot.
pub fn explain_cell(
  snapshot : AiContextSnapshot,
  subject : String,
) -> Result[ExplainCellAnswer, ExplanationQueryError] {
  guard snapshot.cells.search_by(cell => cell.id == subject) is Some(index) else {
    return Err(CellOutsideObservedRegion(subject))
  }
  let focus = snapshot.cells[index]
  let active_inputs = focus.last_dynamic_dependencies.map(id => {
    explanation_input(snapshot.cells, id)
  })
  let inactive_inputs = focus.static_references
    .filter(id => !focus.last_dynamic_dependencies.contains(id))
    .map(id => explanation_input(snapshot.cells, id))
  Ok({
    schema_version: 1,
    subject,
    scope: explanation_scope(snapshot),
    present: focus.present,
    kind: focus.kind,
    result: focus.result,
    formula: focus.formula,
    active_inputs: ReadOnlyArray::from_array(active_inputs),
    inactive_inputs: ReadOnlyArray::from_array(inactive_inputs),
  })
}

///|
/// Explains the latest bounded edit, if trace and evidence history exist.
pub fn explain_last_change(
  snapshot : AiContextSnapshot,
  subject : String,
) -> LastChangeAnswer? {
  guard snapshot.cells.search_by(cell => cell.id == subject) is Some(_) else {
    return None
  }
  guard snapshot.latest_trace is Some(trace) else { return None }
  guard snapshot.latest_evidence is Some(evidence) else { return None }
  let selected_evidence = match
    evidence.cells.search_by(cell => cell.id == subject) {
    Some(index) => Some(explanation_evidence(evidence.cells[index]))
    None => None
  }
  Some({
    schema_version: 1,
    subject,
    scope: explanation_scope(snapshot),
    edit: trace.edit,
    outcome: trace.outcome,
    evidence: selected_evidence,
    trace: {
      recomputed: readonly_string_copy(trace.recomputed),
      changed: readonly_string_copy(trace.changed),
      unchanged: readonly_string_copy(trace.unchanged),
    },
  })
}

///|
fn explanation_evidence(cell : AiContextEvidenceCell) -> ExplanationEvidence {
  {
    classification: cell.classification,
    before_status: cell.before_result_status,
    before_result: explanation_result_display(cell.before_result),
    after_status: cell.after_result_status,
    after_result: explanation_result_display(cell.after_result),
  }
}

///|
fn explanation_result_display(result : String) -> String {
  guard result.strip_prefix("Ok(") is Some(inner) else { return result }
  guard inner.strip_suffix(")") is Some(value) else { return result }
  "\{value}"
}

///|
fn explanation_scope(snapshot : AiContextSnapshot) -> ExplanationScope {
  {
    max_cells: snapshot.max_cells,
    truncated: snapshot.truncated,
    region: readonly_string_copy(snapshot.region),
  }
}

///|
fn readonly_string_copy(items : Array[String]) -> ReadOnlyArray[String] {
  ReadOnlyArray::from_array(items[:].to_owned())
}

///|
fn explanation_input(
  cells : Array[AiContextCell],
  id : String,
) -> ExplanationInput {
  match cells.search_by(cell => cell.id == id) {
    Some(index) => { id, observed: true, result: Some(cells[index].result) }
    None => { id, observed: false, result: None }
  }
}
