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
        view_snapshots(emit, model, step),
      ]),
    ]),
  ])
}

///|
fn view_hero(model : Model) -> @rabbita.Html {
  let schema = model.scenario.schema_version
  let step = current_step(model)
  let total = model.scenario.steps.length()
  @html.header(class="hero", [
    @html.div(class="hero-copy", [
      @html.div(class="eyebrow", "incr · typed spreadsheet · Rabbita"),
      @html.h1(model.scenario.title),
      @html.p(model.scenario.summary),
    ]),
    @html.div(class="hero-readout", [
      view_readout("current step", "\{step.index}/\{total}"),
      view_readout("operation", step.operation),
      view_readout("watching", model.scenario.cells.join(" · ")),
      view_readout("schema", "v\{schema}"),
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
      @html.h2("Scenario"),
      @html.p("A fixed worksheet story; no editing in this demo."),
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
  let label = if active {
    "Current scenario step \{number} of \{total}: \{step.operation}"
  } else {
    "Show scenario step \{number} of \{total}: \{step.operation}"
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
      @html.span(class="step-list-operation", step.operation),
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
      @html.span(
        class="step-kicker",
        "walkthrough step \{step.index} / \{total}",
      ),
      @html.h2(step.operation),
      @html.p(class="step-story", step_story(step)),
      @html.p(class="outcome", [
        @html.span(class="outcome-label", "applied"),
        @html.code(friendly_outcome(step.outcome)),
      ]),
      @html.div(class="walkthrough-map", [
        @html.span(class="sr-only", "Walkthrough order: edit, trace, evidence."),
        @html.span(class="walkthrough-node", "edit"),
        @html.span(
          class="walkthrough-arrow",
          attrs=@html.Attrs::build().aria_hidden("true"),
          "→",
        ),
        @html.span(class="walkthrough-node", "trace"),
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
      @html.h3("Follow the trace"),
      @html.p(
        "Read left to right: first what incr checked, then which results changed or stayed stable.",
      ),
    ]),
    @html.div(class="trace-buckets", [
      view_trace_bucket(
        emit,
        "1 · checked again",
        "Formula cells incr re-read for this edit.",
        "violet",
        step.trace.recomputed,
      ),
      view_trace_bucket(
        emit,
        "2 · changed result",
        "Re-read cells whose displayed value moved.",
        "green",
        step.trace.changed,
      ),
      view_trace_bucket(
        emit,
        "3 · same result",
        "Re-read cells that stayed stable after checking.",
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
    [@html.span(class="empty-chip", "none this step")]
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
      @html.h3("Choose the cell to follow"),
      @html.p(
        "Trace chips and worksheet cells both focus the evidence card below.",
      ),
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
      .aria_label("Select worksheet cell \{cell}: \{state}, \{kind}, \{result}"),
    [
      @html.span(class="cell-address", cell),
      @html.span(class="cell-status", state),
      @html.span(class="cell-kind", kind),
      @html.span(class="cell-value", result),
    ],
  )
}

///|
fn view_snapshots(
  emit : @rabbita.Emit[Msg],
  model : Model,
  step : @demo.WorksheetStepViewModel,
) -> @rabbita.Html {
  let focused = focused_snapshot(model, step)
  let content = match focused {
    Some(change) =>
      @html.div(class="snapshot-list", [
        view_snapshot_change(change),
        view_secondary_snapshots(emit, step, change.cell),
      ])
    None => @html.div(class="snapshot-empty", "No snapshots captured.")
  }
  @html.section(class="snapshot-panel", [
    @html.div(class="section-heading", [
      @html.h3("Evidence for the chosen cell"),
      @html.p(
        "Before and after are paired so the focused cell reads like one trace sentence.",
      ),
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
fn view_secondary_snapshots(
  emit : @rabbita.Emit[Msg],
  step : @demo.WorksheetStepViewModel,
  focused_cell : String,
) -> @rabbita.Html {
  let summaries = []
  for change in step.snapshots {
    if change.cell != focused_cell {
      summaries.push(view_snapshot_summary(emit, change))
    }
  }
  if summaries.length() == 0 {
    @html.nothing
  } else {
    @html.div(class="snapshot-secondary", [
      @html.div(class="snapshot-secondary-label", "Other observed cells"),
      @html.div(class="snapshot-summary-list", summaries),
    ])
  }
}

///|
fn view_snapshot_summary(
  emit : @rabbita.Emit[Msg],
  change : @demo.CellSnapshotChangeViewModel,
) -> @rabbita.Html {
  @html.button(
    class="snapshot-summary",
    on_click=emit(SelectCell(change.cell)),
    attrs=@html.Attrs::build().aria_label(
      "Select cell \{change.cell} snapshot diff: \{friendly_kind(change.before.kind)} to \{friendly_kind(change.after.kind)}, \{friendly_snapshot_result(change.after)}",
    ),
    [
      @html.span(class="summary-cell", change.cell),
      @html.span(
        class="summary-transition",
        "\{friendly_kind(change.before.kind)} → \{friendly_kind(change.after.kind)}",
      ),
      @html.span(class="summary-result", friendly_snapshot_result(change.after)),
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
      view_fact("present", if snapshot.present { "yes" } else { "no" }),
      view_fact("kind", friendly_kind(snapshot.kind)),
      view_fact("deps", join_or_dash(snapshot.installed_dependencies)),
      view_fact("refs", join_or_dash(snapshot.static_references)),
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
fn step_story(step : @demo.WorksheetStepViewModel) -> String {
  match step.index {
    1 => "A1 becomes an input cell. No formula depends on it yet."
    2 => "B1 becomes a formula that watches A1, so incr evaluates it once."
    3 => "A1 changes; incr re-checks B1 and its visible result changes."
    4 =>
      "A1 receives the same value; B1 is checked, but the result stays stable."
    5 => "B1 is removed, leaving A1 as the only visible cell."
    _ => "This step shows how the worksheet state moves after one edit."
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
