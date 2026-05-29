///|
/// Serializable, UI-friendly representation of the fixed typed spreadsheet demo.
pub struct FixedScenarioViewModel {
  schema_version : Int
  title : String
  summary : String
  cells : Array[String]
  steps : Array[WorksheetStepViewModel]
  extensions : Map[String, String]
} derive(ToJson, Debug)

///|
/// Serializable representation of one demo step.
pub struct WorksheetStepViewModel {
  index : Int
  operation : String
  outcome : String
  trace : TraceViewModel
  snapshots : Array[CellSnapshotChangeViewModel]
  extensions : Map[String, String]
} derive(ToJson, Debug)

///|
/// Serializable trace buckets for formula cells affected by a step.
pub struct TraceViewModel {
  recomputed : Array[String]
  changed : Array[String]
  unchanged : Array[String]
} derive(ToJson, Debug)

///|
/// Serializable before/after snapshot for one visible cell.
pub struct CellSnapshotChangeViewModel {
  cell : String
  before : CellSnapshotViewModel
  after : CellSnapshotViewModel
} derive(ToJson, Debug)

///|
/// Serializable snapshot of one cell at one side of a step.
pub struct CellSnapshotViewModel {
  cell : String
  present : Bool
  kind : String
  result : String
  result_status : String
  installed_dependencies : Array[String]
  static_references : Array[String]
} derive(ToJson, Debug)

///|
/// Builds the browser-facing view model for the fixed five-step scenario.
pub fn fixed_scenario_view_model() -> FixedScenarioViewModel {
  let steps = run_fixed_scenario_for_view_model()
  let step_models = []
  for index, step in steps {
    step_models.push(step.to_view_model(index + 1))
  }
  {
    schema_version: 1,
    title: "Typed spreadsheet trace demo",
    summary: "Five fixed operations showing input edits, formula installation, changed/unchanged revalidation, and deletion.",
    cells: ["A1", "B1"],
    steps: step_models,
    extensions: Map([]),
  }
}

///|
/// Serializes the fixed scenario view model as JSON for JavaScript consumers.
pub fn fixed_scenario_json() -> String {
  fixed_scenario_view_model().to_json().stringify(indent=2)
}

///|
/// Converts a raw operation-runner result to the serializable UI view model.
fn WorksheetStepResult::to_view_model(
  self : WorksheetStepResult,
  index : Int,
) -> WorksheetStepViewModel {
  {
    index,
    operation: format_op(self.operation),
    outcome: format_outcome(self.outcome),
    trace: trace_view_model(self.trace),
    snapshots: self.cell_snapshots.map(change => {
      snapshot_change_view_model(change)
    }),
    extensions: Map([]),
  }
}

///|
fn trace_view_model(
  trace : @typed_spreadsheet.WorksheetTrace,
) -> TraceViewModel {
  {
    recomputed: cell_id_strings(trace.recomputed),
    changed: cell_id_strings(trace.changed),
    unchanged: cell_id_strings(trace.unchanged),
  }
}

///|
fn snapshot_change_view_model(
  change : CellSnapshotChange,
) -> CellSnapshotChangeViewModel {
  {
    cell: cell_id_to_string(change.id),
    before: snapshot_view_model(change.before),
    after: snapshot_view_model(change.after),
  }
}

///|
fn snapshot_view_model(
  snapshot : @typed_spreadsheet.CellSnapshot,
) -> CellSnapshotViewModel {
  {
    cell: cell_id_to_string(snapshot.id),
    present: snapshot.present,
    kind: snapshot_kind(snapshot),
    result: format_cell_result(snapshot.result),
    result_status: snapshot_result_status(snapshot),
    installed_dependencies: cell_id_strings(snapshot.installed_dependencies),
    static_references: cell_id_strings(snapshot.static_references),
  }
}

///|
fn snapshot_result_status(snapshot : @typed_spreadsheet.CellSnapshot) -> String {
  if !snapshot.present {
    "missing"
  } else {
    cell_result_status(snapshot.result)
  }
}

///|
fn cell_result_status(result : @typed_spreadsheet.CellResult) -> String {
  match result {
    Ok(_) => "ok"
    ParseError(_) => "parse_error"
    TypeError(_) => "type_error"
    RefError(_) => "ref_error"
    CycleError(_) => "cycle_error"
  }
}
