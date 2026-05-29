///|
priv struct ScenarioJson {
  scenario : String
  trace_semantics : String
  steps : Array[StepJson]
} derive(ToJson)

///|
priv struct StepJson {
  operation : String
  outcome : String
  trace : TraceJson
  snapshots : Array[SnapshotChangeJson]
} derive(ToJson)

///|
priv struct TraceJson {
  recomputed : Array[String]
  changed : Array[String]
  unchanged : Array[String]
} derive(ToJson)

///|
priv struct SnapshotChangeJson {
  cell : String
  before : SnapshotJson
  after : SnapshotJson
} derive(ToJson)

///|
priv struct SnapshotJson {
  cell : String
  present : Bool
  kind : String
  result : String
  installed_dependencies : Array[String]
  static_references : Array[String]
} derive(ToJson)

///|
fn render_json(steps : Array[@demo.WorksheetStepResult]) -> String {
  scenario_json(steps).to_json().stringify(indent=2)
}

///|
fn scenario_json(steps : Array[@demo.WorksheetStepResult]) -> ScenarioJson {
  {
    scenario: "typed_spreadsheet_cli_demo",
    trace_semantics: "before/after summary of formula cells after post-operation reads",
    steps: steps.map(step => step_json(step)),
  }
}

///|
fn step_json(step : @demo.WorksheetStepResult) -> StepJson {
  {
    operation: format_op(step.operation),
    outcome: format_outcome(step.outcome),
    trace: trace_json(step.trace),
    snapshots: step.cell_snapshots.map(change => snapshot_change_json(change)),
  }
}

///|
fn trace_json(trace : @typed_spreadsheet.WorksheetTrace) -> TraceJson {
  {
    recomputed: cell_id_strings(trace.recomputed),
    changed: cell_id_strings(trace.changed),
    unchanged: cell_id_strings(trace.unchanged),
  }
}

///|
fn snapshot_change_json(
  change : @demo.CellSnapshotChange,
) -> SnapshotChangeJson {
  {
    cell: cell_id_to_string(change.id),
    before: snapshot_json(change.before),
    after: snapshot_json(change.after),
  }
}

///|
fn snapshot_json(snapshot : @typed_spreadsheet.CellSnapshot) -> SnapshotJson {
  {
    cell: cell_id_to_string(snapshot.id),
    present: snapshot.present,
    kind: snapshot_kind(snapshot),
    result: format_cell_result(snapshot.result),
    installed_dependencies: cell_id_strings(snapshot.installed_dependencies),
    static_references: cell_id_strings(snapshot.static_references),
  }
}

///|
fn snapshot_kind(snapshot : @typed_spreadsheet.CellSnapshot) -> String {
  match snapshot.kind {
    Some(kind) => format_cell_kind(kind)
    None => "missing"
  }
}

///|
fn cell_id_strings(ids : Array[@typed_spreadsheet.CellId]) -> Array[String] {
  ids.map(id => cell_id_to_string(id))
}
