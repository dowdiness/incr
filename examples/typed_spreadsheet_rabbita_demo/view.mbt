///|
fn view(emit : @rabbita.Emit[Msg], model : Model) -> @rabbita.Html {
  let step = current_step(model)
  @html.div(class="app-shell", [
    view_hero(model),
    @html.main_(class="workspace", attrs=@html.Attrs::build().role("main"), [
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
  let schema = model.scenario.schema_version
  @html.header(class="hero", [
    @html.div(class="eyebrow", "incr / typed spreadsheet / rabbita"),
    @html.div(class="hero-copy", [
      @html.h1(model.scenario.title),
      @html.p(model.scenario.summary),
    ]),
    @html.div(class="hero-meta", [
      @html.span(class="meta-pill", "schema v\{schema}"),
      @html.span(class="meta-pill", "fixed 5-step scenario"),
    ]),
  ])
}

///|
fn view_scenario_nav(emit : @rabbita.Emit[Msg], model : Model) -> @rabbita.Html {
  let items = []
  for index, step in model.scenario.steps {
    items.push(view_step_nav_button(emit, model.current, index, step))
  }
  @html.aside(class="scenario-rail", [
    @html.div(class="rail-header", [
      @html.h2("Scenario"),
      @html.p("A fixed worksheet story; no editing in this demo."),
    ]),
    @html.div(class="step-list", attrs=@html.Attrs::build().role("list"), items),
    view_status(model),
  ])
}

///|
fn view_step_nav_button(
  emit : @rabbita.Emit[Msg],
  current : Int,
  index : Int,
  step : @demo.WorksheetStepViewModel,
) -> @rabbita.Html {
  let active = index == current
  let attrs = if active {
    @html.Attrs::build().aria_current("step")
  } else {
    @html.Attrs::build()
  }
  let number = index + 1
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
      @html.span(class="step-kicker", "step \{step.index} / \{total}"),
      @html.h2(step.operation),
      @html.p(class="outcome", [
        @html.span(class="outcome-label", "outcome"),
        @html.code(step.outcome),
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
      @html.h3("Trace buckets"),
      @html.p(
        "Formula cells re-read after the operation, grouped by revision result.",
      ),
    ]),
    @html.div(class="trace-buckets", [
      view_trace_bucket(emit, "recomputed", "violet", step.trace.recomputed),
      view_trace_bucket(emit, "changed", "green", step.trace.changed),
      view_trace_bucket(emit, "unchanged", "amber", step.trace.unchanged),
    ]),
  ])
}

///|
fn view_trace_bucket(
  emit : @rabbita.Emit[Msg],
  label : String,
  tone : String,
  cells : Array[String],
) -> @rabbita.Html {
  @html.div(class="trace-bucket trace-bucket--\{tone}", [
    @html.div(class="trace-bucket-label", label),
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
    [@html.span(class="empty-chip", "none")]
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
      @html.h3("Worksheet grid"),
      @html.p("Click a cell to keep its snapshot diff in focus."),
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
    Some(change) => change.after.kind
    None => "not captured"
  }
  let result = match snapshot {
    Some(change) => change.after.result
    None => "No snapshot"
  }
  @html.button(
    class=class_name,
    on_click=emit(SelectCell(cell)),
    attrs=@html.Attrs::build().aria_label("Select worksheet cell \{cell}"),
    [
      @html.span(class="cell-address", cell),
      @html.span(class="cell-kind", kind),
      @html.span(class="cell-value", result),
    ],
  )
}

///|
fn view_snapshots(
  model : Model,
  step : @demo.WorksheetStepViewModel,
) -> @rabbita.Html {
  let cards = step.snapshots.map(change => view_snapshot_change(model, change))
  @html.section(class="snapshot-panel", [
    @html.div(class="section-heading", [
      @html.h3("Before / after snapshots"),
      @html.p(
        "Snapshots stay in MoonBit; the UI only projects their serialized shape.",
      ),
    ]),
    @html.div(class="snapshot-list", cards),
  ])
}

///|
fn view_snapshot_change(
  model : Model,
  change : @demo.CellSnapshotChangeViewModel,
) -> @rabbita.Html {
  let selected = selected_cell_is(model, change.cell)
  @html.article(class=active_class("snapshot-card", selected), [
    @html.div(class="snapshot-card-header", [
      @html.span(class="snapshot-cell", change.cell),
      @html.span(
        class="snapshot-state",
        if selected {
          "selected"
        } else {
          "observed"
        },
      ),
    ]),
    @html.div(class="snapshot-sides", [
      view_snapshot_side("before", change.before),
      view_snapshot_side("after", change.after),
    ]),
  ])
}

///|
fn view_snapshot_side(
  label : String,
  snapshot : @demo.CellSnapshotViewModel,
) -> @rabbita.Html {
  @html.div(class="snapshot-side", [
    @html.div(class="snapshot-side-label", label),
    @html.div(class=snapshot_result_class(snapshot), snapshot.result),
    @html.div(class="snapshot-facts", [
      view_fact("present", if snapshot.present { "yes" } else { "no" }),
      view_fact("kind", snapshot.kind),
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
      if !change.after.present {
        "grid-cell grid-cell--missing"
      } else if change.after.result.contains("RefError") ||
        change.after.result.contains("TypeError") ||
        change.after.result.contains("CycleError") {
        "grid-cell grid-cell--error"
      } else {
        "grid-cell grid-cell--ready"
      }
  }
}

///|
fn snapshot_result_class(snapshot : @demo.CellSnapshotViewModel) -> String {
  if !snapshot.present {
    "snapshot-result snapshot-result--missing"
  } else if snapshot.result.contains("RefError") ||
    snapshot.result.contains("TypeError") ||
    snapshot.result.contains("CycleError") {
    "snapshot-result snapshot-result--error"
  } else {
    "snapshot-result snapshot-result--ok"
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
