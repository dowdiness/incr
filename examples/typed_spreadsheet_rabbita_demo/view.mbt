///|
fn view(emit : @rabbita.Emit[Msg], model : Model) -> @rabbita.Html {
  @html.div(
    class=app_shell_class(model),
    on_click=emit(CloseIntro),
    on_keydown=event => emit(HandleAppKey(event)),
    [
      view_live_region(model),
      @html.main_(class="sheet-workspace", [view_sheet(emit, model)]),
      view_demo_intro(model.intro_visible, model.overlay),
      view_panel_rail_left(emit, model),
      view_panel_rail_right(emit, model),
      view_overlay(emit, model),
    ],
  )
}

///|
/// A permanently-mounted, visually hidden polite live region so status and
/// error updates are announced to screen readers even when the (default-closed)
/// editor overlay — which owns the visible status line — is not in the DOM.
fn view_live_region(model : Model) -> @rabbita.Html {
  let announcement = match model.error {
    Some(message) => "\{model.status} \{message}"
    None => model.status
  }
  @html.div(
    class="sr-only",
    attrs=@html.Attrs::build().role("status").aria_live("polite"),
    announcement,
  )
}

///|
fn app_shell_class(model : Model) -> String {
  "app-shell app-shell--\{appearance_label(model.appearance)}"
}

///|
fn view_demo_intro(
  intro_visible : Bool,
  overlay : OverlayPanel,
) -> @rabbita.Html {
  if !intro_visible {
    @html.nothing
  } else {
    match overlay {
      OverlayClosed =>
        @html.aside(
          class="demo-intro",
          attrs=@html.Attrs::build()
            .role("complementary")
            .aria_label("What this demo shows")
            .on_click(event => {
              event.stop_propagation()
              @rabbita.none
            }),
          [
            @html.p(class="demo-intro-kicker", "incr demo"),
            @html.h2(
              class="demo-intro-title",
              "Edit one cell. Watch only the necessary work happen.",
            ),
            @html.p(
              class="demo-intro-copy",
              "Cells are MoonBit incremental computations; formulas track the cells they read. Use the bottom rail: edit a value, then open trace and evidence.",
            ),
          ],
        )
      _ => @html.nothing
    }
  }
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
    Some(message) => @html.span(class="status-error", message)
    None => @html.nothing
  }
  // Visual only — announcements come from the persistent view_live_region so a
  // closed overlay does not swallow them and an open one does not double-speak.
  @html.div(class=class_name, [
    @html.span(class="status-text", model.status),
    error,
  ])
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
      attrs=@html.Attrs::build()
        .role("grid")
        .tabindex(0)
        .aria_label(
          "50 by 50 typed spreadsheet. Arrow keys move selection, Enter edits the cell.",
        )
        .aria_colcount("\{grid_column_count()}")
        .aria_rowcount("\{grid_row_count()}")
        .aria_activedescendant("cell-\{model.selected_cell}")
        .on_keydown(event => grid_key_cmd(emit, model, event)),
      children,
    ),
  ])
}

///|
/// Keyboard handling for the grid container. Wired through `Attrs::on_keydown`
/// (not the element-level `on_keydown=`) so the callback receives the live
/// `@dom.KeyboardEvent`: returning a `Cmd` lets us `prevent_default` so arrow
/// keys move the selection instead of scrolling the focused grid, and `Enter`
/// opens the inline editor (giving keyboard users a way into in-grid editing).
///
/// The modifier guard mirrors `should_ignore_keyboard` (model.mbt), which acts
/// on the value-type `@html.Keyboard` from the document-level handler; the two
/// keyboard types are distinct, so the four checks are repeated rather than
/// shared.
fn grid_key_cmd(
  emit : @rabbita.Emit[Msg],
  model : Model,
  event : @dom.KeyboardEvent,
) -> @rabbita.Cmd {
  let modified = event.is_composing() ||
    event.alt_key() ||
    event.ctrl_key() ||
    event.meta_key()
  if model.editing_cell is Some(_) || modified {
    return @rabbita.none
  }
  let msg = match event.key() {
    "ArrowLeft" => Some(MoveSelection(-1, 0))
    "ArrowRight" => Some(MoveSelection(1, 0))
    "ArrowUp" => Some(MoveSelection(0, -1))
    "ArrowDown" => Some(MoveSelection(0, 1))
    "Enter" => Some(BeginInlineEdit(model.selected_cell))
    "Escape" => Some(CancelSelected)
    _ => None
  }
  match msg {
    Some(next) => {
      event.prevent_default()
      event.stop_propagation()
      emit(next)
    }
    None => @rabbita.none
  }
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
  let snapshot = grid_snapshot_for(model, cell)
  let selected = selected_cell_is(model, cell)
  let dirty = draft_is_dirty(model, cell)
  let editing = inline_editing_cell_is(model, cell)
  let status = grid_status_label(snapshot)
  let kind = friendly_grid_kind(snapshot)
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
        "Select cell \{cell}: \{status}, \{kind}, \{friendly_grid_result(snapshot)}",
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
  snapshot : GridCellSnapshot,
  editing : Bool,
) -> @rabbita.Html {
  if editing {
    // Focus is driven by the after-render BeginInlineEdit Cmd (main.mbt), which
    // is reliable under vdom patching; no `autofocus` attribute (it would be a
    // second, racing focus source).
    @html.input(
      id=inline_editor_id(cell),
      class="cell-inline-input",
      value=draft_for(model, cell),
      inputmode="text",
      on_input=value => emit(UpdateDraft(cell, value)),
      attrs=@html.Attrs::build()
        .aria_label("Edit \{cell} directly")
        .on_keydown(event => inline_edit_key_cmd(emit, cell, event))
        .on_blur(_ => emit(ApplyInlineEdit(cell))),
      @html.nothing,
    )
  } else {
    @html.span(class="cell-value", grid_cell_display_value(snapshot))
  }
}

///|
/// The DOM id of a cell's inline editor input. Single source of truth shared by
/// the view (which renders it) and the focus Cmd (which looks it up).
fn inline_editor_id(cell : String) -> String {
  "inline-editor-\{cell}"
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
        view_trace_bucket(
          emit, "recomputed", "Dependency check or evaluation ran after the edit.",
          recomputed,
        ),
        view_trace_bucket(
          emit, "changed", "The visible result changed.", changed,
        ),
        view_trace_bucket(
          emit, "unchanged", "Work ran, but the result stayed the same.", unchanged,
        ),
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
      @html.p(
        class="snapshot-panel-help",
        "Before/after snapshots show what the MoonBit worksheet engine observed around the last edit.",
      ),
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
  match cells {
    [] => [@html.span(class="empty-chip", "none")]
    _ =>
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
  guard model.last_step is Some(step) else { return None }
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
  model.editing_cell == Some(cell)
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
  snapshot : GridCellSnapshot,
  selected : Bool,
  dirty : Bool,
  editing : Bool,
) -> String {
  let selected_class = active_class(grid_cell_state_class(snapshot), selected)
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
/// The display-relevant state of a cell. Replaces a stringly-typed status so the
/// styling/label helpers below match exhaustively — a new CellResult variant is
/// a compile error here, not a silent fallthrough.
enum CellStatus {
  Missing
  Ready
  ParseErr
  TypeErr
  RefErr
  CycleErr
}

///|
fn cell_status_from(
  present : Bool,
  result : @typed_spreadsheet.CellResult,
) -> CellStatus {
  guard present else { return Missing }
  match result {
    Ok(_) => Ready
    ParseError(_) => ParseErr
    TypeError(_) => TypeErr
    RefError(_) => RefErr
    CycleError(_) => CycleErr
  }
}

///|
fn snapshot_cell_status(
  snapshot : @typed_spreadsheet.CellSnapshot,
) -> CellStatus {
  cell_status_from(snapshot.present, snapshot.result)
}

///|
fn grid_cell_status(snapshot : GridCellSnapshot) -> CellStatus {
  cell_status_from(snapshot.present, snapshot.result)
}

///|
fn grid_cell_state_class(snapshot : GridCellSnapshot) -> String {
  match grid_cell_status(snapshot) {
    Missing => "grid-cell grid-cell--missing"
    Ready => "grid-cell grid-cell--ready"
    ParseErr | TypeErr | RefErr | CycleErr => "grid-cell grid-cell--error"
  }
}

///|
fn status_label(status : CellStatus) -> String {
  match status {
    Ready => "ready"
    Missing => "empty"
    ParseErr => "parse error"
    TypeErr => "type error"
    RefErr => "ref error"
    CycleErr => "cycle error"
  }
}

///|
fn snapshot_status_label(snapshot : @typed_spreadsheet.CellSnapshot) -> String {
  status_label(snapshot_cell_status(snapshot))
}

///|
fn grid_status_label(snapshot : GridCellSnapshot) -> String {
  status_label(grid_cell_status(snapshot))
}

///|
fn kind_label(present : Bool, kind : @typed_spreadsheet.CellKind?) -> String {
  if !present {
    "empty"
  } else {
    match kind {
      Some(Input) => "input"
      Some(Formula) => "formula"
      None => "unknown"
    }
  }
}

///|
fn friendly_kind(snapshot : @typed_spreadsheet.CellSnapshot) -> String {
  kind_label(snapshot.present, snapshot.kind)
}

///|
fn friendly_grid_kind(snapshot : GridCellSnapshot) -> String {
  kind_label(snapshot.present, snapshot.kind)
}

///|
fn result_label(
  present : Bool,
  result : @typed_spreadsheet.CellResult,
) -> String {
  if !present {
    "Empty cell"
  } else {
    result_repr(result)
  }
}

///|
fn friendly_snapshot_result(
  snapshot : @typed_spreadsheet.CellSnapshot,
) -> String {
  result_label(snapshot.present, snapshot.result)
}

///|
fn friendly_grid_result(snapshot : GridCellSnapshot) -> String {
  result_label(snapshot.present, snapshot.result)
}

///|
/// Human label for a cell result: the bare value for `Ok` (`Int(10)`), the
/// variant repr for an error. Replaces fragile `strip_prefix("Ok(")` string
/// surgery — matching the enum keeps the `Ok` unwrap honest.
fn result_repr(result : @typed_spreadsheet.CellResult) -> String {
  match result {
    Ok(value) => repr(value)
    other => repr(other)
  }
}

///|
/// Human label for an operation outcome shown in the status line.
fn outcome_label(outcome : @demo.OpOutcome) -> String {
  match outcome {
    SetFormulaAst(Ok(_)) => "Applied"
    SetFormulaAst(Err(error)) => repr(error)
    SetInput(result) => result_repr(result)
    Delete(result) => result_repr(result)
  }
}

///|
fn grid_cell_display_value(snapshot : GridCellSnapshot) -> String {
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
  match snapshot_cell_status(snapshot) {
    Missing => "snapshot-result snapshot-result--missing"
    Ready => "snapshot-result snapshot-result--ok"
    ParseErr | TypeErr | RefErr | CycleErr =>
      "snapshot-result snapshot-result--error"
  }
}

///|
fn join_or_dash(values : Array[String]) -> String {
  match values {
    [] => "—"
    _ => values.join(", ")
  }
}
