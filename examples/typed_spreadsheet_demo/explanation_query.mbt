///|
/// A deterministic explanation query failed before producing an answer.
pub(all) enum ExplanationQueryError {
  CellOutsideObservedRegion(String)
} derive(ToJson, Debug, Eq)

///|
/// Stable spreadsheet kinds exposed by explanation answers.
pub(all) enum ExplanationCellKind {
  ExplanationInputCell
  ExplanationFormulaCell
  ExplanationMissingCell
  ExplanationUnknownCell(String)
} derive(ToJson, Debug, Eq)

///|
/// Stable error categories exposed by explanation results.
pub(all) enum ExplanationErrorKind {
  ParseFailure
  TypeFailure
  ReferenceFailure
  CycleFailure
} derive(ToJson, Debug, Eq)

///|
/// A typed current or historical cell result.
pub(all) enum ExplanationResult {
  Value(AiContextValue)
  Missing
  Error(ExplanationErrorKind, String)
  UnknownResult(String, String)
} derive(ToJson, Debug, Eq)

///|
/// Whether one formula input was resolved in the bounded context.
pub(all) enum ExplanationInputState {
  Observed(ExplanationResult)
  OutsideObservedRegion
} derive(ToJson, Debug, Eq)

///|
/// Stable latest-edit classifications exposed by explanation evidence.
pub(all) enum ExplanationChange {
  Changed
  Unchanged
  Recomputed
  Unobserved
  UnknownChange(String)
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
  state : ExplanationInputState
} derive(ToJson, Debug, Eq)

///|
/// One structured cell error found within the bounded observed region.
pub struct ExplanationObservedError {
  id : String
  kind : ExplanationErrorKind
  message : String
} derive(ToJson, Debug, Eq)

///|
/// How one observed cell depends on the queried subject.
pub struct ExplanationDependent {
  id : String
  static_reference : Bool
  active_dependency : Bool
} derive(ToJson, Debug, Eq)

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
  classification : ExplanationChange
  before_result : ExplanationResult
  after_result : ExplanationResult
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
/// Structured errors from one bounded observed region.
pub struct ObservedErrorsAnswer {
  schema_version : Int
  scope : ExplanationScope
  errors : ReadOnlyArray[ExplanationObservedError]
} derive(ToJson, Debug)

///|
/// Observed-region cells that depend on one subject.
pub struct ObservedDependentsAnswer {
  schema_version : Int
  subject : String
  scope : ExplanationScope
  dependents : ReadOnlyArray[ExplanationDependent]
} derive(ToJson, Debug)

///|
/// Deterministic semantic facts explaining one observed spreadsheet cell.
pub struct ExplainCellAnswer {
  schema_version : Int
  subject : String
  scope : ExplanationScope
  present : Bool
  kind : ExplanationCellKind
  result : ExplanationResult
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
    kind: explanation_cell_kind(focus.kind),
    result: explanation_result(focus.result),
    formula: focus.formula,
    active_inputs: ReadOnlyArray::from_array(active_inputs),
    inactive_inputs: ReadOnlyArray::from_array(inactive_inputs),
  })
}

///|
/// Returns structured cell errors found within the snapshot's bounded region.
pub fn observed_errors(snapshot : AiContextSnapshot) -> ObservedErrorsAnswer {
  let errors = snapshot.cells.filter_map(cell => {
    match explanation_result(cell.result) {
      Error(kind, message) => Some({ id: cell.id, kind, message })
      _ => None
    }
  })
  {
    schema_version: 1,
    scope: explanation_scope(snapshot),
    errors: ReadOnlyArray::from_array(errors),
  }
}

///|
/// Finds dependents among observed cells without claiming sheet-wide scope.
/// The subject itself does not need to be inside the observed region.
pub fn observed_dependents(
  snapshot : AiContextSnapshot,
  subject : String,
) -> ObservedDependentsAnswer {
  let dependents = snapshot.cells.filter_map(cell => {
    let static_reference = cell.static_references.contains(subject)
    let active_dependency = cell.last_dynamic_dependencies.contains(subject)
    if static_reference || active_dependency {
      Some({ id: cell.id, static_reference, active_dependency })
    } else {
      None
    }
  })
  {
    schema_version: 1,
    subject,
    scope: explanation_scope(snapshot),
    dependents: ReadOnlyArray::from_array(dependents),
  }
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
fn explanation_cell_kind(kind : String) -> ExplanationCellKind {
  match kind {
    "input" => ExplanationInputCell
    "formula" => ExplanationFormulaCell
    "missing" => ExplanationMissingCell
    other => ExplanationUnknownCell(other)
  }
}

///|
fn explanation_result(result : AiContextResult) -> ExplanationResult {
  match result.status {
    "ok" =>
      match result.value {
        Some(value) => Value(value)
        None => UnknownResult(result.status, result.repr)
      }
    "missing" => Missing
    "parse_error" => explanation_error(ParseFailure, result)
    "type_error" => explanation_error(TypeFailure, result)
    "ref_error" => explanation_error(ReferenceFailure, result)
    "cycle_error" => explanation_error(CycleFailure, result)
    status => UnknownResult(status, result.repr)
  }
}

///|
fn explanation_error(
  kind : ExplanationErrorKind,
  result : AiContextResult,
) -> ExplanationResult {
  Error(kind, result.error.unwrap_or(result.repr))
}

///|
fn explanation_change(classification : String) -> ExplanationChange {
  match classification {
    "changed" => Changed
    "unchanged" => Unchanged
    "recomputed" => Recomputed
    "unobserved" => Unobserved
    other => UnknownChange(other)
  }
}

///|
fn explanation_evidence(cell : AiContextEvidenceCell) -> ExplanationEvidence {
  {
    classification: explanation_change(cell.classification),
    before_result: explanation_result(cell.before),
    after_result: explanation_result(cell.after),
  }
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
    Some(index) =>
      { id, state: Observed(explanation_result(cells[index].result)) }
    None => { id, state: OutsideObservedRegion }
  }
}
