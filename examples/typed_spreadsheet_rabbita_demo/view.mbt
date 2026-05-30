///|
fn view(emit : @rabbita.Emit[Msg], model : Model) -> @rabbita.Html {
  @html.div(
    class=app_shell_class(model),
    on_keydown=event => emit(HandleAppKey(event)),
    [
      @html.main_(class="sheet-workspace", [view_sheet(emit, model)]),
      view_panel_rail_left(emit, model),
      view_panel_rail_right(emit, model),
      view_overlay(emit, model),
    ],
  )
}

///|
fn app_shell_class(model : Model) -> String {
  "app-shell app-shell--\{appearance_label(model.appearance)}"
}

///|
fn view_panel_rail_left(
  emit : @rabbita.Emit[Msg],
  model : Model,
) -> @rabbita.Html {
  @html.nav(
    class="panel-rail panel-rail--left",
    attrs=@html.Attrs::build().aria_label("Sheet editing"),
    [
      view_overlay_button(
        emit,
        model,
        EditorOverlay,
        "edit",
        model.selected_cell,
      ),
    ],
  )
}

///|
fn view_panel_rail_right(
  emit : @rabbita.Emit[Msg],
  model : Model,
) -> @rabbita.Html {
  @html.nav(
    class="panel-rail panel-rail--right",
    attrs=@html.Attrs::build().aria_label("Sheet inspectors"),
    [
      view_overlay_button(
        emit,
        model,
        TraceOverlay,
        "trace",
        trace_badge(model),
      ),
      view_overlay_button(
        emit,
        model,
        SnapshotOverlay,
        "evidence",
        evidence_badge(model),
      ),
    ],
  )
}

///|
fn view_status(model : Model) -> @rabbita.Html {
  let class_name = match model.error {
    Some(_) => "status-line status-line--error"
    None => "status-line"
  }
  let error = match model.error {
    Some(message) =>
      @html.span(
        class="status-error",
        attrs=@html.Attrs::build().role("alert"),
        message,
      )
    None => @html.nothing
  }
  @html.div(
    class=class_name,
    attrs=@html.Attrs::build().role("status").aria_live("polite"),
    [@html.span(class="status-text", model.status), error],
  )
}

///|
fn view_overlay_button(
  emit : @rabbita.Emit[Msg],
  model : Model,
  overlay : OverlayPanel,
  label : String,
  badge : String,
) -> @rabbita.Html {
  let active = model.overlay == overlay
  @html.button(
    type_="button",
    class=active_class("quiet-button overlay-toggle", active),
    on_click=emit(SetOverlay(overlay)),
    attrs=@html.Attrs::build()
      .aria_pressed(if active { "true" } else { "false" })
      .aria_label("Toggle \{label} inspector"),
    [
      @html.span(class="toggle-label", label),
      @html.span(class="toggle-badge", badge),
    ],
  )
}

///|
fn view_appearance_button(
  emit : @rabbita.Emit[Msg],
  model : Model,
  appearance : Appearance,
  label : String,
) -> @rabbita.Html {
  let active = model.appearance == appearance
  @html.button(
    type_="button",
    class=active_class("appearance-option", active),
    on_click=emit(SetAppearance(appearance)),
    attrs=@html.Attrs::build()
      .aria_pressed(if active { "true" } else { "false" })
      .aria_label("Use \{label} appearance"),
    label,
  )
}

///|
fn view_formula_bar(emit : @rabbita.Emit[Msg], model : Model) -> @rabbita.Html {
  let draft = draft_for(model, model.selected_cell)
  @html.form(
    class="formula-bar",
    on_submit=emit(ApplySelected),
    attrs=@html.Attrs::build().aria_label("Formula editor"),
    [
      @html.div(class="formula-cell", [
        @html.span(class="formula-cell-label", "cell"),
        @html.span(class="formula-cell-address", model.selected_cell),
        @html.span(class="formula-last-edit", "last: \{model.last_edit}"),
      ]),
      @html.label(
        class="sr-only",
        for_="cell-editor-input",
        "Edit \{model.selected_cell}",
      ),
      @html.input(
        id="cell-editor-input",
        class="formula-input",
        value=draft,
        placeholder="10 or =A1",
        inputmode="text",
        on_input=value => emit(UpdateDraft(model.selected_cell, value)),
        attrs=@html.Attrs::build()
          .aria_label("Formula text for \{model.selected_cell}")
          .aria_keyshortcuts("Enter Escape"),
        @html.nothing,
      ),
      @html.div(class="formula-actions", [
        @html.button(
          type_="submit",
          class="primary-action",
          disabled=draft.trim().is_empty(),
          attrs=@html.Attrs::build().aria_label(
            "Apply edit to \{model.selected_cell}",
          ),
          "Apply",
        ),
        @html.button(
          type_="button",
          class="quiet-button",
          on_click=emit(CancelSelected),
          attrs=@html.Attrs::build().aria_label(
            "Cancel draft for \{model.selected_cell}",
          ),
          "Cancel",
        ),
        @html.button(
          type_="button",
          class="quiet-button danger-action",
          on_click=emit(DeleteSelected),
          attrs=@html.Attrs::build().aria_label("Delete \{model.selected_cell}"),
          "Delete",
        ),
      ]),
      view_examples(emit),
    ],
  )
}

///|
fn view_examples(emit : @rabbita.Emit[Msg]) -> @rabbita.Html {
  let examples = ["10", "15", "=A1", "=A1 + 1", "=A1 * 2", "=if(A1 > 10, 1, 0)"]
  @html.div(class="example-strip", [
    @html.span(class="example-label", "examples"),
    @html.div(
      class="example-chips",
      examples.map(example => {
        @html.button(
          type_="button",
          class="example-chip",
          on_click=emit(UseExample(example)),
          attrs=@html.Attrs::build().aria_label("Use example \{example}"),
          example,
        )
      }),
    ),
  ])
}

///|
fn view_sheet(emit : @rabbita.Emit[Msg], model : Model) -> @rabbita.Html {
  let columns = column_labels()
  let children = [@html.div(class="sheet-corner", "")]
  for column in columns {
    children.push(view_column_header(column))
  }
  for row in 1..<=grid_row_count() {
    children.push(view_row_header("\{row}"))
    for column_index, column in columns {
      let cell = "\{column}\{row}"
      children.push(view_grid_cell(emit, model, cell, row, column_index + 1))
    }
  }
  @html.section(class="sheet-stage", [
    @html.div(
      class="sheet-grid",
      on_keydown=event => emit(HandleGridKey(event)),
      attrs=@html.Attrs::build()
        .role("grid")
        .tabindex(0)
        .aria_label("50 by 50 typed spreadsheet. Arrow keys move selection.")
        .aria_colcount("\{grid_column_count()}")
        .aria_rowcount("\{grid_row_count()}")
        .aria_activedescendant("cell-\{model.selected_cell}"),
      children,
    ),
  ])
}

///|
fn view_key_hint(key : String, label : String) -> @rabbita.Html {
  @html.span(class="key-hint", [
    @html.span(class="keycap", key),
    @html.span(class="key-label", label),
  ])
}

///|
fn view_column_header(label : String) -> @rabbita.Html {
  @html.div(
    class="sheet-column-header",
    attrs=@html.Attrs::build().role("columnheader"),
    label,
  )
}

///|
fn view_row_header(label : String) -> @rabbita.Html {
  @html.div(
    class="sheet-row-header",
    attrs=@html.Attrs::build().role("rowheader"),
    label,
  )
}

///|
fn view_grid_cell(
  emit : @rabbita.Emit[Msg],
  model : Model,
  cell : String,
  row_index : Int,
  column_index : Int,
) -> @rabbita.Html {
  let snapshot = model.sheet.inspect_cell(cell_id(model, cell))
  let selected = selected_cell_is(model, cell)
  let dirty = draft_is_dirty(model, cell)
  let editing = inline_editing_cell_is(model, cell)
  let status = snapshot_status_label(snapshot)
  let kind = friendly_kind(snapshot)
  let selected_text = if selected { "true" } else { "false" }
  let click = if editing { @rabbita.none } else { emit(SelectCell(cell)) }
  @html.div(
    id="cell-\{cell}",
    class=grid_cell_class(snapshot, selected, dirty, editing),
    on_click=click,
    attrs=@html.Attrs::build()
      .role("gridcell")
      .aria_selected(selected_text)
      .aria_rowindex("\{row_index}")
      .aria_colindex("\{column_index}")
      .aria_label(
        "Select cell \{cell}: \{status}, \{kind}, \{friendly_snapshot_result(snapshot)}",
      )
      .on_dblclick(_ => emit(BeginInlineEdit(cell))),
    view_cell_content(emit, model, cell, snapshot, editing),
  )
}

///|
fn view_cell_content(
  emit : @rabbita.Emit[Msg],
  model : Model,
  cell : String,
  snapshot : @typed_spreadsheet.CellSnapshot,
  editing : Bool,
) -> @rabbita.Html {
  if editing {
    @html.input(
      id="inline-editor-\{cell}",
      class="cell-inline-input",
      value=draft_for(model, cell),
      autofocus=true,
      inputmode="text",
      on_input=value => emit(UpdateDraft(cell, value)),
      attrs=@html.Attrs::build()
        .aria_label("Edit \{cell} directly")
        .on_keydown(event => inline_edit_key_cmd(emit, cell, event))
        .on_blur(_ => emit(ApplyInlineEdit(cell))),
      @html.nothing,
    )
  } else {
    @html.span(class="cell-value", cell_display_value(snapshot))
  }
}

///|
fn inline_edit_key_cmd(
  emit : @rabbita.Emit[Msg],
  cell : String,
  event : @dom.KeyboardEvent,
) -> @rabbita.Cmd {
  match event.key() {
    "Enter" => {
      event.prevent_default()
      event.stop_propagation()
      emit(ApplyInlineEdit(cell))
    }
    "Escape" => {
      event.prevent_default()
      event.stop_propagation()
      emit(CancelSelected)
    }
    _ => @rabbita.none
  }
}

///|
fn view_overlay(emit : @rabbita.Emit[Msg], model : Model) -> @rabbita.Html {
  match model.overlay {
    OverlayClosed => @html.nothing
    EditorOverlay => view_editor_overlay(emit, model)
    TraceOverlay => view_trace_overlay(emit, model)
    SnapshotOverlay => view_snapshot_overlay(emit, model)
  }
}

///|
fn view_editor_overlay(
  emit : @rabbita.Emit[Msg],
  model : Model,
) -> @rabbita.Html {
  @html.aside(
    class="inspector-panel inspector-panel--editor",
    attrs=@html.Attrs::build().role("complementary").aria_label("Edit panel"),
    [
      view_inspector_header(emit, "Edit", "formula, status, and sheet controls"),
      view_status(model),
      view_formula_bar(emit, model),
      @html.div(class="panel-controls", [
        @html.button(
          type_="button",
          class="quiet-button reset-action",
          on_click=emit(ResetSheet),
          attrs=@html.Attrs::build().aria_label("Reset the sheet"),
          "reset",
        ),
        @html.div(class="appearance-switch", [
          view_appearance_button(emit, model, Paper, "paper"),
          view_appearance_button(emit, model, Night, "night"),
        ]),
      ]),
      @html.div(class="keyboard-hint keyboard-hint--panel", [
        view_key_hint("↑↓←→", "move"),
        view_key_hint("Enter", "apply"),
        view_key_hint("Esc", "cancel"),
      ]),
    ],
  )
}

///|
fn view_trace_overlay(
  emit : @rabbita.Emit[Msg],
  model : Model,
) -> @rabbita.Html {
  let (recomputed, changed, unchanged) = trace_cells(model)
  @html.aside(
    class="inspector-panel inspector-panel--trace",
    attrs=@html.Attrs::build()
      .role("complementary")
      .aria_label("Trace inspector"),
    [
      view_inspector_header(emit, "Trace", "what the engine revisited"),
      @html.div(class="trace-buckets", [
        view_trace_bucket(emit, "checked", "Formula cells re-read.", recomputed),
        view_trace_bucket(emit, "changed", "Visible value moved.", changed),
        view_trace_bucket(emit, "stable", "Re-read with same value.", unchanged),
      ]),
    ],
  )
}

///|
fn view_snapshot_overlay(
  emit : @rabbita.Emit[Msg],
  model : Model,
) -> @rabbita.Html {
  let content = match focused_snapshot(model) {
    Some(change) => view_snapshot_change(change)
    None =>
      @html.div(
        class="snapshot-empty",
        "Apply an edit to capture before/after evidence.",
      )
  }
  @html.aside(
    class="inspector-panel inspector-panel--snapshot",
    attrs=@html.Attrs::build()
      .role("complementary")
      .aria_label("Snapshot inspector"),
    [
      view_inspector_header(emit, "Evidence", "before and after the last edit"),
      content,
    ],
  )
}

///|
fn view_inspector_header(
  emit : @rabbita.Emit[Msg],
  title : String,
  subtitle : String,
) -> @rabbita.Html {
  @html.div(class="inspector-header", [
    @html.div(class="inspector-title", [@html.h2(title), @html.p(subtitle)]),
    @html.button(
      type_="button",
      class="quiet-button close-button",
      on_click=emit(SetOverlay(OverlayClosed)),
      attrs=@html.Attrs::build().aria_label("Close inspector"),
      "Close",
    ),
  ])
}

///|
fn view_trace_bucket(
  emit : @rabbita.Emit[Msg],
  label : String,
  help : String,
  cells : Array[String],
) -> @rabbita.Html {
  @html.div(class="trace-bucket", [
    @html.div(class="trace-bucket-top", [
      @html.span(class="trace-bucket-label", label),
      @html.span(class="trace-count", "\{cells.length()}"),
    ]),
    @html.p(class="trace-bucket-help", help),
    @html.div(class="cell-chip-row", cell_chips(emit, cells, label)),
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
        type_="button",
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
fn focused_snapshot(model : Model) -> @demo.CellSnapshotChange? {
  match model.last_step {
    Some(step) =>
      match
        step.cell_snapshots.search_by(change => {
          @demo.cell_id_to_string(change.id) == model.selected_cell
        }) {
        Some(index) => step.cell_snapshots.get(index)
        None =>
          match step.cell_snapshots {
            [first, ..] => Some(first)
            [] => None
          }
      }
    None => None
  }
}

///|
fn view_snapshot_change(change : @demo.CellSnapshotChange) -> @rabbita.Html {
  @html.article(class="snapshot-evidence", [
    @html.div(class="snapshot-evidence-header", [
      @html.span(class="snapshot-cell", @demo.cell_id_to_string(change.id)),
      @html.span(class="snapshot-state", "last edit"),
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
      view_fact("exists", if snapshot.present { "yes" } else { "no" }),
      view_fact("kind", friendly_kind(snapshot)),
      view_fact(
        "deps",
        join_or_dash(@demo.cell_id_strings(snapshot.installed_dependencies)),
      ),
      view_fact(
        "refs",
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
fn trace_badge(model : Model) -> String {
  let (recomputed, changed, unchanged) = trace_cells(model)
  "\{recomputed.length() + changed.length() + unchanged.length()}"
}

///|
fn evidence_badge(model : Model) -> String {
  match model.last_step {
    Some(step) => "\{step.cell_snapshots.length()}"
    None => "0"
  }
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
fn selected_cell_is(model : Model, cell : String) -> Bool {
  model.selected_cell == cell
}

///|
fn inline_editing_cell_is(model : Model, cell : String) -> Bool {
  match model.editing_cell {
    Some(editing) => editing == cell
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
fn grid_cell_class(
  snapshot : @typed_spreadsheet.CellSnapshot,
  selected : Bool,
  dirty : Bool,
  editing : Bool,
) -> String {
  let selected_class = active_class(cell_state_class(snapshot), selected)
  let dirty_class = if dirty {
    selected_class + " is-dirty"
  } else {
    selected_class
  }
  if editing {
    dirty_class + " is-editing"
  } else {
    dirty_class
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
fn cell_display_value(snapshot : @typed_spreadsheet.CellSnapshot) -> String {
  if !snapshot.present {
    ""
  } else {
    match snapshot.result {
      Ok(value) => cell_value_text(value)
      ParseError(_) => "parse error"
      TypeError(_) => "type error"
      RefError(_) => "ref error"
      CycleError(_) => "cycle"
    }
  }
}

///|
fn cell_value_text(value : @typed_spreadsheet.CellValue) -> String {
  match value {
    Int(value) => "\{value}"
    Bool(value) => if value { "true" } else { "false" }
    Text(value) => value
    Blank => ""
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
