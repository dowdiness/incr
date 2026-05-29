///|
fn view(emit : @rabbita.Emit[Msg], model : Model) -> @rabbita.Html {
  let step = current_step(model)
  @html.div(class="app-shell", [
    view_hero(model),
    @html.main_(class="workspace", [
      view_scenario_nav(emit, model),
      @html.section(class="step-panel", [
        view_step_header(emit, model, step),
        view_trace(emit, step),
        view_grid(emit, model, step),
        view_snapshots(model, step),
      ]),
    ]),
  ])
}

///|
fn view_hero(model : Model) -> @rabbita.Html {
  let step = current_step(model)
  let total = model.scenario.steps.length()
  @html.header(class="hero", [
    @html.div(class="hero-copy", [
      @html.div(class="eyebrow", "incremental engine · typed spreadsheet"),
      @html.h1(model.scenario.title),
      @html.p(
        "A quiet trace of one formula: install B1, change A1, and watch what the incremental engine checks.",
      ),
    ]),
    @html.div(class="hero-readout", [
      view_readout("step", "\{step.index}/\{total}"),
      view_readout("edit", step_detail(step)),
      view_readout("cells", model.scenario.cells.join(" · ")),
    ]),
  ])
}

///|
fn view_readout(label : String, value : String) -> @rabbita.Html {
  @html.div(class="readout-cell", [
    @html.span(class="readout-label", label),
    @html.span(class="readout-value", value),
  ])
}

///|
fn view_scenario_nav(emit : @rabbita.Emit[Msg], model : Model) -> @rabbita.Html {
  let items = []
  let step = current_step(model)
  let total = model.scenario.steps.length()
  for index, step in model.scenario.steps {
    items.push(
      @html.li(
        class="step-list-entry",
        view_step_nav_button(emit, model.current, index, total, step),
      ),
    )
  }
  @html.aside(class="scenario-rail", [
    @html.div(class="rail-header", [
      @html.h2("Step \{step.index} / \{total}"),
      @html.p(step_title(step)),
    ]),
    @html.ol(class="step-list", items),
    view_status(model),
  ])
}

///|
fn view_step_nav_button(
  emit : @rabbita.Emit[Msg],
  current : Int,
  index : Int,
  total : Int,
  step : @demo.WorksheetStepViewModel,
) -> @rabbita.Html {
  let active = index == current
  let number = index + 1
  let operation = step_title(step)
  let label = if active {
    "Current scenario step \{number} of \{total}: \{operation}"
  } else {
    "Show scenario step \{number} of \{total}: \{operation}"
  }
  let attrs = if active {
    @html.Attrs::build().aria_current("step").aria_label(label)
  } else {
    @html.Attrs::build().aria_label(label)
  }
  @html.button(
    class=active_class("step-list-item", active),
    on_click=emit(SelectStep(index)),
    attrs~,
    [
      @html.span(class="step-list-number", "0\{number}"),
      @html.span(class="step-list-operation", operation),
    ],
  )
}

///|
fn view_status(model : Model) -> @rabbita.Html {
  let error = match model.error {
    Some(message) =>
      @html.div(
        class="error-message",
        attrs=@html.Attrs::build().role("alert"),
        message,
      )
    None => @html.nothing
  }
  @html.div(class="status-stack", [
    @html.div(
      class="status-message",
      attrs=@html.Attrs::build().role("status").aria_live("polite"),
      model.status,
    ),
    error,
  ])
}

///|
fn view_step_header(
  emit : @rabbita.Emit[Msg],
  model : Model,
  step : @demo.WorksheetStepViewModel,
) -> @rabbita.Html {
  let total = model.scenario.steps.length()
  @html.div(class="step-header", [
    @html.div(class="step-title-block", [
      @html.span(class="step-kicker", "step \{step.index} / \{total}"),
      @html.h2(step_title(step)),
      @html.p(class="step-story", step_story(step)),
      @html.p(class="outcome", [
        @html.span(class="outcome-label", "result"),
        @html.code(friendly_outcome(step.outcome)),
      ]),
      @html.div(class="walkthrough-map", [
        @html.span(
          class="sr-only",
          "Walkthrough order: edit, engine, evidence.",
        ),
        @html.span(class="walkthrough-node", "edit"),
        @html.span(
          class="walkthrough-arrow",
          attrs=@html.Attrs::build().aria_hidden("true"),
          "→",
        ),
        @html.span(class="walkthrough-node", "engine"),
        @html.span(
          class="walkthrough-arrow",
          attrs=@html.Attrs::build().aria_hidden("true"),
          "→",
        ),
        @html.span(class="walkthrough-node", "evidence"),
      ]),
    ]),
    @html.div(class="step-controls", [
      @html.button(
        class="control-button",
        disabled=model.current == 0,
        on_click=emit(PrevStep),
        attrs=@html.Attrs::build().aria_label("Show previous scenario step"),
        "Previous",
      ),
      @html.button(
        class="control-button control-button--primary",
        disabled=model.current + 1 >= total,
        on_click=emit(NextStep),
        attrs=@html.Attrs::build().aria_label("Show next scenario step"),
        "Next",
      ),
    ]),
  ])
}

///|
fn view_trace(
  emit : @rabbita.Emit[Msg],
  step : @demo.WorksheetStepViewModel,
) -> @rabbita.Html {
  @html.section(class="trace-panel", [
    @html.div(class="section-heading", [
      @html.h3("What the engine checked"),
      @html.p(
        "The incremental engine records what it checked, what changed, and what stayed stable.",
      ),
    ]),
    @html.div(class="trace-buckets", [
      view_trace_bucket(
        emit,
        "1 · checked",
        "Formulas the engine re-read after the edit.",
        "violet",
        step.trace.recomputed,
      ),
      view_trace_bucket(
        emit,
        "2 · changed",
        "Re-read cells with a new visible value.",
        "green",
        step.trace.changed,
      ),
      view_trace_bucket(
        emit,
        "3 · stable",
        "Re-read cells whose value stayed the same.",
        "amber",
        step.trace.unchanged,
      ),
    ]),
  ])
}

///|
fn view_trace_bucket(
  emit : @rabbita.Emit[Msg],
  label : String,
  help : String,
  tone : String,
  cells : Array[String],
) -> @rabbita.Html {
  @html.div(class="trace-bucket trace-bucket--\{tone}", [
    @html.div(class="trace-bucket-label", label),
    @html.p(class="trace-bucket-help", help),
    @html.div(class="trace-chip-row", cell_chips(emit, cells, label)),
  ])
}

///|
fn cell_chips(
  emit : @rabbita.Emit[Msg],
  cells : Array[String],
  source : String,
) -> Array[@rabbita.Html] {
  if cells.length() == 0 {
    [@html.span(class="empty-chip", "none here")]
  } else {
    cells.map(cell => {
      @html.button(
        class="cell-chip",
        on_click=emit(SelectCell(cell)),
        attrs=@html.Attrs::build().aria_label(
          "Select cell \{cell} from \{source} trace bucket",
        ),
        cell,
      )
    })
  }
}

///|
fn view_grid(
  emit : @rabbita.Emit[Msg],
  model : Model,
  step : @demo.WorksheetStepViewModel,
) -> @rabbita.Html {
  let cells = model.scenario.cells.map(cell => {
    view_grid_cell(emit, model, step, cell)
  })
  @html.section(class="grid-panel", [
    @html.div(class="section-heading", [
      @html.h3("Choose a cell"),
      @html.p("Select A1 or B1 to compare before and after."),
    ]),
    @html.div(class="worksheet-grid", cells),
  ])
}

///|
fn view_grid_cell(
  emit : @rabbita.Emit[Msg],
  model : Model,
  step : @demo.WorksheetStepViewModel,
  cell : String,
) -> @rabbita.Html {
  let snapshot = snapshot_for(step, cell)
  let selected = selected_cell_is(model, cell)
  let class_name = active_class(cell_state_class(snapshot), selected)
  let kind = match snapshot {
    Some(change) => friendly_kind(change.after.kind)
    None => "not captured"
  }
  let kind_label = cell_kind_label(kind)
  let result = match snapshot {
    Some(change) => friendly_snapshot_result(change.after)
    None => "No snapshot"
  }
  let state = cell_status_label(snapshot)
  let pressed = if selected { "true" } else { "false" }
  @html.button(
    class=class_name,
    on_click=emit(SelectCell(cell)),
    attrs=@html.Attrs::build()
      .aria_pressed(pressed)
      .aria_label(
        "Select worksheet cell \{cell}: \{state}, \{kind_label}, \{result}",
      ),
    [
      @html.span(class="cell-address", cell),
      @html.span(class="cell-status", state),
      @html.span(class="cell-kind", kind_label),
      @html.span(class="cell-value", result),
    ],
  )
}

///|
fn view_snapshots(
  model : Model,
  step : @demo.WorksheetStepViewModel,
) -> @rabbita.Html {
  let focused = focused_snapshot(model, step)
  let content = match focused {
    Some(change) => view_snapshot_change(change)
    None => @html.div(class="snapshot-empty", "No snapshots captured.")
  }
  @html.section(class="snapshot-panel", [
    @html.div(class="section-heading", [
      @html.h3("Before and after"),
      @html.p("Compare the selected cell across this edit."),
    ]),
    content,
  ])
}

///|
fn focused_snapshot(
  model : Model,
  step : @demo.WorksheetStepViewModel,
) -> @demo.CellSnapshotChangeViewModel? {
  match model.selected_cell {
    Some(cell) =>
      match snapshot_for(step, cell) {
        Some(change) => Some(change)
        None => step.snapshots.get(0)
      }
    None => step.snapshots.get(0)
  }
}

///|
fn view_snapshot_change(
  change : @demo.CellSnapshotChangeViewModel,
) -> @rabbita.Html {
  @html.article(
    class="snapshot-evidence snapshot-evidence--primary is-active",
    [
      @html.div(class="snapshot-evidence-header", [
        @html.span(class="snapshot-cell", change.cell),
        @html.span(class="snapshot-state", "selected"),
      ]),
      @html.div(class="snapshot-sides", [
        view_snapshot_side("before", change.before),
        view_snapshot_side("after", change.after),
      ]),
    ],
  )
}

///|
fn view_snapshot_side(
  label : String,
  snapshot : @demo.CellSnapshotViewModel,
) -> @rabbita.Html {
  @html.div(class="snapshot-side", [
    @html.div(class="snapshot-side-label", label),
    @html.div(class="snapshot-result-status", snapshot_status_label(snapshot)),
    @html.div(
      class=snapshot_result_class(snapshot),
      friendly_snapshot_result(snapshot),
    ),
    @html.div(class="snapshot-facts", [
      view_fact("cell exists", if snapshot.present { "yes" } else { "no" }),
      view_fact("cell type", friendly_kind(snapshot.kind)),
      view_fact(
        "installed dependencies",
        join_or_dash(snapshot.installed_dependencies),
      ),
      view_fact("static references", join_or_dash(snapshot.static_references)),
    ]),
  ])
}

///|
fn view_fact(label : String, value : String) -> @rabbita.Html {
  @html.div(class="fact-row", [
    @html.span(class="fact-label", label),
    @html.span(class="fact-value", value),
  ])
}

///|
fn snapshot_for(
  step : @demo.WorksheetStepViewModel,
  cell : String,
) -> @demo.CellSnapshotChangeViewModel? {
  match step.snapshots.search_by(change => change.cell == cell) {
    Some(index) => step.snapshots.get(index)
    None => None
  }
}

///|
fn step_title(step : @demo.WorksheetStepViewModel) -> String {
  match step.index {
    1 => "Setup input A1"
    2 => "Install formula B1"
    3 => "Change A1"
    4 => "Re-enter A1"
    5 => "Delete B1"
    _ => friendly_operation(step.operation)
  }
}

///|
fn step_detail(step : @demo.WorksheetStepViewModel) -> String {
  match step.index {
    1 => "A1 = Int(10)"
    2 => "B1 = A1 + Int(1)"
    3 => "A1 = Int(15)"
    4 => "A1 = Int(15) again"
    5 => "Remove B1"
    _ => friendly_operation(step.operation)
  }
}

///|
fn step_story(step : @demo.WorksheetStepViewModel) -> String {
  match step.index {
    1 => "Setup: A1 becomes an input cell. No formula is watching it yet."
    2 => "B1 starts watching A1. The engine checks B1 and stores Int(11)."
    3 => "A1 changes. The engine checks B1, and its visible result moves."
    4 =>
      "A1 receives the same value; B1 is checked, but the result stays stable."
    5 => "B1 is removed, leaving A1 as the only visible cell."
    _ => "This step shows how the worksheet changes after one edit."
  }
}

///|
fn friendly_operation(operation : String) -> String {
  match operation.strip_prefix("SetInput ") {
    Some(rest) => "Set input " + rest.to_owned()
    None =>
      match operation.strip_prefix("SetFormulaAst ") {
        Some(rest) => "Install formula " + rest.to_owned()
        None => operation
      }
  }
}

///|
fn friendly_outcome(outcome : String) -> String {
  if outcome == "Ok(())" {
    "Applied"
  } else {
    match ok_value(outcome) {
      Some(value) => "Stored \{value}"
      None => friendly_result(outcome)
    }
  }
}

///|
fn friendly_snapshot_result(snapshot : @demo.CellSnapshotViewModel) -> String {
  match snapshot.result_status {
    "missing" => "Empty cell"
    _ => friendly_result(snapshot.result)
  }
}

///|
fn friendly_result(result : String) -> String {
  match ok_value(result) {
    Some(value) => value
    None => result
  }
}

///|
fn ok_value(result : String) -> String? {
  match result.strip_prefix("Ok(") {
    Some(rest) =>
      match rest.strip_suffix(")") {
        Some(value) => Some(value.to_owned())
        None => None
      }
    None => None
  }
}

///|
fn friendly_kind(kind : String) -> String {
  match kind {
    "missing" => "empty"
    other => other
  }
}

///|
fn cell_kind_label(kind : String) -> String {
  match kind {
    "empty" => "no definition"
    "not captured" => "not captured"
    other => other + " cell"
  }
}

///|
fn selected_cell_is(model : Model, cell : String) -> Bool {
  match model.selected_cell {
    Some(selected) => selected == cell
    None => false
  }
}

///|
fn active_class(base : String, active : Bool) -> String {
  if active {
    base + " is-active"
  } else {
    base
  }
}

///|
fn cell_state_class(snapshot : @demo.CellSnapshotChangeViewModel?) -> String {
  match snapshot {
    None => "grid-cell grid-cell--unknown"
    Some(change) =>
      match change.after.result_status {
        "missing" => "grid-cell grid-cell--missing"
        "ok" => "grid-cell grid-cell--ready"
        _ => "grid-cell grid-cell--error"
      }
  }
}

///|
fn cell_status_label(snapshot : @demo.CellSnapshotChangeViewModel?) -> String {
  match snapshot {
    None => "not captured"
    Some(change) => snapshot_status_label(change.after)
  }
}

///|
fn snapshot_status_label(snapshot : @demo.CellSnapshotViewModel) -> String {
  match snapshot.result_status {
    "ok" => "ready"
    "missing" => "empty"
    "parse_error" => "parse error"
    "type_error" => "type error"
    "ref_error" => "ref error"
    "cycle_error" => "cycle error"
    _ => "unknown"
  }
}

///|
fn snapshot_result_class(snapshot : @demo.CellSnapshotViewModel) -> String {
  match snapshot.result_status {
    "missing" => "snapshot-result snapshot-result--missing"
    "ok" => "snapshot-result snapshot-result--ok"
    _ => "snapshot-result snapshot-result--error"
  }
}

///|
fn join_or_dash(values : Array[String]) -> String {
  if values.length() == 0 {
    "—"
  } else {
    values.join(", ")
  }
}
