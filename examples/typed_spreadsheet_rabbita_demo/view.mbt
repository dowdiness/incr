///|
fn view(emit : @rabbita.Emit[Msg], model : Model) -> @rabbita.Html {
  @html.div(class="app-shell", [
    view_hero(model),
    @html.main_(class="workspace", [
      view_editor_rail(emit, model),
      @html.section(class="step-panel editor-stage", [
        view_editor_header(emit, model),
        view_editor_form(emit, model),
        view_trace(emit, model),
        view_grid(emit, model),
        view_snapshots(model),
      ]),
    ]),
  ])
}

///|
fn view_hero(model : Model) -> @rabbita.Html {
  @html.header(class="hero", [
    @html.div(class="hero-copy", [
      @html.div(class="eyebrow", "incremental engine · editable sheet"),
      @html.h1("Typed sheet editor"),
      @html.p(
        "Edit a four-cell sheet and watch the MoonBit worksheet recalculate exactly what depends on the change.",
      ),
    ]),
    @html.div(class="hero-readout", [
      view_readout("selected", model.selected_cell),
      view_readout("last edit", model.last_edit),
      view_readout("grammar", "Int · =A1 + 1 · =if(A1 > 10, 1, 0)"),
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
fn view_editor_rail(emit : @rabbita.Emit[Msg], model : Model) -> @rabbita.Html {
  let items = model.cells.map(cell => {
    @html.li(class="step-list-entry", view_cell_nav_button(emit, model, cell))
  })
  @html.aside(class="scenario-rail editor-rail", [
    @html.div(class="rail-header", [
      @html.h2("Editing \{model.selected_cell}"),
      @html.p("Integers and a tiny formula grammar. No ranges yet."),
    ]),
    @html.ol(class="step-list", items),
    view_status(model),
  ])
}

///|
fn view_cell_nav_button(
  emit : @rabbita.Emit[Msg],
  model : Model,
  cell : String,
) -> @rabbita.Html {
  let selected = selected_cell_is(model, cell)
  let snapshot = model.sheet.inspect_cell(cell_id(model, cell))
  let label = if selected {
    "Current editable cell \{cell}: \{snapshot_status_label(snapshot)}, \{friendly_kind(snapshot)}"
  } else {
    "Edit cell \{cell}: \{snapshot_status_label(snapshot)}, \{friendly_kind(snapshot)}"
  }
  let attrs = if selected {
    @html.Attrs::build().aria_current("true").aria_label(label)
  } else {
    @html.Attrs::build().aria_label(label)
  }
  @html.button(
    class=active_class("step-list-item", selected),
    on_click=emit(SelectCell(cell)),
    attrs~,
    [
      @html.span(class="step-list-number", cell),
      @html.span(
        class="step-list-operation",
        friendly_snapshot_result(snapshot),
      ),
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
fn view_editor_header(
  emit : @rabbita.Emit[Msg],
  model : Model,
) -> @rabbita.Html {
  @html.div(class="step-header", [
    @html.div(class="step-title-block", [
      @html.span(class="step-kicker", "editable prototype"),
      @html.h2("Change \{model.selected_cell}, then read the trace"),
      @html.p(
        class="step-story",
        "Each apply runs a real typed-spreadsheet operation, captures before/after snapshots, and records which formula cells were checked.",
      ),
      @html.p(class="outcome", [
        @html.span(class="outcome-label", "last result"),
        @html.code(last_outcome(model)),
      ]),
      @html.div(class="walkthrough-map", [
        @html.span(
          class="sr-only",
          "Workflow order: edit, apply, engine trace, evidence.",
        ),
        @html.span(class="walkthrough-node", "edit"),
        @html.span(
          class="walkthrough-arrow",
          attrs=@html.Attrs::build().aria_hidden("true"),
          "→",
        ),
        @html.span(class="walkthrough-node", "apply"),
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
        on_click=emit(ResetSheet),
        attrs=@html.Attrs::build().aria_label("Reset the tiny spreadsheet"),
        "Reset",
      ),
    ]),
  ])
}

///|
fn view_editor_form(emit : @rabbita.Emit[Msg], model : Model) -> @rabbita.Html {
  let draft = draft_for(model, model.selected_cell)
  @html.section(class="edit-panel", [
    @html.div(class="section-heading", [
      @html.h3("Edit one cell"),
      @html.p(
        "Type an integer or a small formula, then apply it to the MoonBit worksheet.",
      ),
    ]),
    @html.div(class="editor-card", [
      @html.label(
        class="editor-label",
        for_="cell-editor-input",
        model.selected_cell,
      ),
      @html.input(
        id="cell-editor-input",
        class="editor-input",
        value=draft,
        placeholder="10 or =A1 + 1",
        on_input=value => emit(UpdateDraft(model.selected_cell, value)),
        @html.nothing,
      ),
      @html.div(class="editor-actions", [
        @html.button(
          class="control-button control-button--primary",
          disabled=draft.trim().is_empty(),
          on_click=emit(ApplySelected),
          attrs=@html.Attrs::build().aria_label(
            "Apply edit to \{model.selected_cell}",
          ),
          "Apply edit",
        ),
        @html.button(
          class="control-button",
          on_click=emit(DeleteSelected),
          attrs=@html.Attrs::build().aria_label("Delete \{model.selected_cell}"),
          "Delete cell",
        ),
      ]),
      view_examples(emit),
    ]),
  ])
}

///|
fn view_examples(emit : @rabbita.Emit[Msg]) -> @rabbita.Html {
  let examples = ["10", "15", "=A1 + 1", "=A1 * 2", "=if(A1 > 10, 1, 0)"]
  @html.div(class="example-row", [
    @html.span(class="example-label", "examples"),
    @html.div(
      class="trace-chip-row",
      examples.map(example => {
        @html.button(
          class="cell-chip example-chip",
          on_click=emit(UseExample(example)),
          attrs=@html.Attrs::build().aria_label("Use example \{example}"),
          example,
        )
      }),
    ),
  ])
}

///|
fn view_trace(emit : @rabbita.Emit[Msg], model : Model) -> @rabbita.Html {
  let (recomputed, changed, unchanged) = trace_cells(model)
  @html.section(class="trace-panel", [
    @html.div(class="section-heading", [
      @html.h3("What the engine checked"),
      @html.p(
        "Formula cells appear here only when the last edit made the incremental engine revisit them.",
      ),
    ]),
    @html.div(class="trace-buckets", [
      view_trace_bucket(
        emit, "1 · checked", "Formulas re-read after the edit.", "violet", recomputed,
      ),
      view_trace_bucket(
        emit, "2 · changed", "Re-read cells with a new visible value.", "green",
        changed,
      ),
      view_trace_bucket(
        emit, "3 · stable", "Re-read cells whose value stayed the same.", "amber",
        unchanged,
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
fn view_grid(emit : @rabbita.Emit[Msg], model : Model) -> @rabbita.Html {
  let cells = model.cells.map(cell => view_grid_cell(emit, model, cell))
  @html.section(class="grid-panel", [
    @html.div(class="section-heading", [
      @html.h3("Sheet"),
      @html.p(
        "Select a cell to edit its draft text and inspect its last before/after evidence.",
      ),
    ]),
    @html.div(class="worksheet-grid editor-grid", cells),
  ])
}

///|
fn view_grid_cell(
  emit : @rabbita.Emit[Msg],
  model : Model,
  cell : String,
) -> @rabbita.Html {
  let snapshot = model.sheet.inspect_cell(cell_id(model, cell))
  let selected = selected_cell_is(model, cell)
  let class_name = active_class(cell_state_class(snapshot), selected)
  let state = snapshot_status_label(snapshot)
  let kind = friendly_kind(snapshot)
  let pressed = if selected { "true" } else { "false" }
  @html.button(
    class=class_name,
    on_click=emit(SelectCell(cell)),
    attrs=@html.Attrs::build()
      .aria_pressed(pressed)
      .aria_label("Select worksheet cell \{cell}: \{state}, \{kind}"),
    [
      @html.span(class="cell-address", cell),
      @html.span(class="cell-status", state),
      @html.span(class="cell-kind", "\{kind} cell"),
      @html.span(class="cell-value", friendly_snapshot_result(snapshot)),
      @html.span(class="cell-draft", "draft: \{draft_for(model, cell)}"),
    ],
  )
}

///|
fn view_snapshots(model : Model) -> @rabbita.Html {
  let content = match focused_snapshot(model) {
    Some(change) => view_snapshot_change(change)
    None =>
      @html.div(
        class="snapshot-empty",
        "Apply an edit to capture before/after evidence.",
      )
  }
  @html.section(class="snapshot-panel", [
    @html.div(class="section-heading", [
      @html.h3("Before and after"),
      @html.p("The selected cell is compared across the last applied edit."),
    ]),
    content,
  ])
}

///|
fn focused_snapshot(model : Model) -> @demo.CellSnapshotChange? {
  match model.last_step {
    Some(step) =>
      match
        step.cell_snapshots.search_by(change => {
          @demo.cell_id_to_string(change.id) == model.selected_cell
        }) {
        Some(index) => step.cell_snapshots.get(index)
        None => step.cell_snapshots.get(0)
      }
    None => None
  }
}

///|
fn view_snapshot_change(change : @demo.CellSnapshotChange) -> @rabbita.Html {
  @html.article(
    class="snapshot-evidence snapshot-evidence--primary is-active",
    [
      @html.div(class="snapshot-evidence-header", [
        @html.span(class="snapshot-cell", @demo.cell_id_to_string(change.id)),
        @html.span(class="snapshot-state", "last edit"),
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
  snapshot : @typed_spreadsheet.CellSnapshot,
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
      view_fact("cell type", friendly_kind(snapshot)),
      view_fact(
        "installed dependencies",
        join_or_dash(@demo.cell_id_strings(snapshot.installed_dependencies)),
      ),
      view_fact(
        "static references",
        join_or_dash(@demo.cell_id_strings(snapshot.static_references)),
      ),
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
fn trace_cells(model : Model) -> (Array[String], Array[String], Array[String]) {
  match model.last_step {
    Some(step) =>
      (
        @demo.cell_id_strings(step.trace.recomputed),
        @demo.cell_id_strings(step.trace.changed),
        @demo.cell_id_strings(step.trace.unchanged),
      )
    None => ([], [], [])
  }
}

///|
fn last_outcome(model : Model) -> String {
  match model.last_step {
    Some(step) => friendly_outcome(@demo.format_outcome(step.outcome))
    None => "Ready"
  }
}

///|
fn selected_cell_is(model : Model, cell : String) -> Bool {
  model.selected_cell == cell
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
fn cell_state_class(snapshot : @typed_spreadsheet.CellSnapshot) -> String {
  match cell_result_status(snapshot) {
    "missing" => "grid-cell grid-cell--missing"
    "ok" => "grid-cell grid-cell--ready"
    _ => "grid-cell grid-cell--error"
  }
}

///|
fn snapshot_status_label(snapshot : @typed_spreadsheet.CellSnapshot) -> String {
  match cell_result_status(snapshot) {
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
fn cell_result_status(snapshot : @typed_spreadsheet.CellSnapshot) -> String {
  if !snapshot.present {
    "missing"
  } else {
    match snapshot.result {
      Ok(_) => "ok"
      ParseError(_) => "parse_error"
      TypeError(_) => "type_error"
      RefError(_) => "ref_error"
      CycleError(_) => "cycle_error"
    }
  }
}

///|
fn friendly_kind(snapshot : @typed_spreadsheet.CellSnapshot) -> String {
  if !snapshot.present {
    "empty"
  } else {
    match snapshot.kind {
      Some(Input) => "input"
      Some(Formula) => "formula"
      None => "unknown"
    }
  }
}

///|
fn friendly_snapshot_result(
  snapshot : @typed_spreadsheet.CellSnapshot,
) -> String {
  if !snapshot.present {
    "Empty cell"
  } else {
    friendly_result(@demo.format_cell_result(snapshot.result))
  }
}

///|
fn snapshot_result_class(snapshot : @typed_spreadsheet.CellSnapshot) -> String {
  match cell_result_status(snapshot) {
    "missing" => "snapshot-result snapshot-result--missing"
    "ok" => "snapshot-result snapshot-result--ok"
    _ => "snapshot-result snapshot-result--error"
  }
}

///|
fn friendly_outcome(outcome : String) -> String {
  if outcome == "Ok(())" {
    "Applied"
  } else {
    friendly_result(outcome)
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
fn join_or_dash(values : Array[String]) -> String {
  if values.length() == 0 {
    "—"
  } else {
    values.join(", ")
  }
}
