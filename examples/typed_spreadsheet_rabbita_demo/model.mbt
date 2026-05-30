///|
struct CellDraft {
  cell : String
  text : String
}

///|
enum Appearance {
  Paper
  Night
} derive(Eq)

///|
enum OverlayPanel {
  OverlayClosed
  EditorOverlay
  TraceOverlay
  SnapshotOverlay
} derive(Eq)

///|
struct Model {
  sheet : @typed_spreadsheet.Worksheet
  cells : Array[String]
  drafts : Array[CellDraft]
  committed : Array[CellDraft]
  selected_cell : String
  editing_cell : String?
  last_step : @demo.WorksheetStepResult?
  last_edit : String
  status : String
  error : String?
  appearance : Appearance
  overlay : OverlayPanel
}

///|
enum Msg {
  SelectCell(String)
  UpdateDraft(String, String)
  UseExample(String)
  ApplySelected
  DeleteSelected
  ResetSheet
  CancelSelected
  BeginInlineEdit(String)
  ApplyInlineEdit(String)
  HandleGridKey(@html.Keyboard)
  HandleAppKey(@html.Keyboard)
  SetAppearance(Appearance)
  SetOverlay(OverlayPanel)
}

///|
fn init_model() -> Model {
  let sheet = @typed_spreadsheet.Worksheet(
    @incr.Runtime(),
    @typed_spreadsheet.SheetId(1),
  )
  let cells = grid_cells()
  let seed_drafts = [
    { cell: "A1", text: "10" },
    { cell: "B1", text: "=A1 + 1" },
  ]
  let base = {
    sheet,
    cells,
    drafts: seed_drafts,
    committed: seed_drafts,
    selected_cell: "B1",
    editing_cell: None,
    last_step: None,
    last_edit: "Seed sheet",
    status: "Ready. Edit the formula bar or move across the sheet with arrow keys.",
    error: None,
    appearance: Paper,
    overlay: OverlayClosed,
  }
  let seeded = apply_text_edit(
    apply_text_edit(base, "A1", "10"),
    "B1",
    "=A1 + 1",
  )
  {
    ..seeded,
    selected_cell: "B1",
    editing_cell: None,
    last_step: None,
    last_edit: "Seed sheet",
    status: "Ready. Edit the formula bar or move across the sheet with arrow keys.",
    error: None,
    overlay: OverlayClosed,
  }
}

///|
fn update(msg : Msg, model : Model) -> Model {
  match msg {
    SelectCell(cell) => { ..select_cell(model, cell), editing_cell: None }
    UpdateDraft(cell, text) =>
      {
        ..select_cell(model, cell),
        drafts: update_draft(model.drafts, cell, text),
        status: "Drafting \{cell}.",
        error: None,
      }
    UseExample(text) =>
      {
        ..model,
        drafts: update_draft(model.drafts, model.selected_cell, text),
        status: "Loaded example text for \{model.selected_cell}.",
        error: None,
      }
    ApplySelected =>
      apply_text_edit(
        model,
        model.selected_cell,
        draft_for(model, model.selected_cell),
      )
    DeleteSelected => delete_selected(model)
    ResetSheet => reset_model(model)
    CancelSelected => cancel_selected(model)
    BeginInlineEdit(cell) => begin_inline_edit(model, cell)
    ApplyInlineEdit(cell) => apply_inline_edit(model, cell)
    HandleGridKey(event) => handle_grid_key(model, event)
    HandleAppKey(event) => handle_app_key(model, event)
    SetAppearance(appearance) => set_appearance(model, appearance)
    SetOverlay(overlay) => set_overlay(model, overlay)
  }
}

///|
fn reset_model(model : Model) -> Model {
  let appearance = model.appearance
  model.sheet.dispose()
  { ..init_model(), appearance, }
}

///|
fn select_cell(model : Model, cell : String) -> Model {
  { ..model, selected_cell: cell, status: "Editing \{cell}.", error: None }
}

///|
fn handle_app_key(model : Model, event : @html.Keyboard) -> Model {
  if should_ignore_keyboard(event) {
    model
  } else {
    match event.key() {
      "Escape" => cancel_selected(model)
      _ => model
    }
  }
}

///|
fn handle_grid_key(model : Model, event : @html.Keyboard) -> Model {
  if model.editing_cell is Some(_) || should_ignore_keyboard(event) {
    model
  } else {
    match event.key() {
      "ArrowLeft" => move_selection(model, -1, 0)
      "ArrowRight" => move_selection(model, 1, 0)
      "ArrowUp" => move_selection(model, 0, -1)
      "ArrowDown" => move_selection(model, 0, 1)
      "Enter" =>
        apply_text_edit(
          model,
          model.selected_cell,
          draft_for(model, model.selected_cell),
        )
      "Escape" => cancel_selected(model)
      _ => model
    }
  }
}

///|
fn begin_inline_edit(model : Model, cell : String) -> Model {
  {
    ..select_cell(model, cell),
    editing_cell: Some(cell),
    status: "Editing \{cell} in the grid.",
    error: None,
  }
}

///|
fn should_ignore_keyboard(event : @html.Keyboard) -> Bool {
  event.is_composing() ||
  event.alt_key() ||
  event.ctrl_key() ||
  event.meta_key()
}

///|
fn move_selection(model : Model, delta_col : Int, delta_row : Int) -> Model {
  match model.cells.search_by(cell => cell == model.selected_cell) {
    Some(index) => {
      let col_count = grid_column_count()
      let row_count = grid_row_count()
      if row_count == 0 {
        model
      } else {
        let row = index / col_count
        let col = index % col_count
        let next_row = clamp_int(row + delta_row, 0, row_count - 1)
        let next_col = clamp_int(col + delta_col, 0, col_count - 1)
        let next_index = next_row * col_count + next_col
        if next_index >= 0 && next_index < model.cells.length() {
          let next_cell = model.cells[next_index]
          if next_cell == model.selected_cell {
            model
          } else {
            {
              ..select_cell(model, next_cell),
              status: "Selected \{next_cell}.",
            }
          }
        } else {
          model
        }
      }
    }
    None => model
  }
}

///|
fn clamp_int(value : Int, low : Int, high : Int) -> Int {
  if value < low {
    low
  } else if value > high {
    high
  } else {
    value
  }
}

///|
fn set_appearance(model : Model, appearance : Appearance) -> Model {
  {
    ..model,
    appearance,
    status: "Appearance set to \{appearance_label(appearance)}.",
    error: None,
  }
}

///|
fn set_overlay(model : Model, overlay : OverlayPanel) -> Model {
  let next = if model.overlay == overlay { OverlayClosed } else { overlay }
  { ..model, overlay: next, status: overlay_status(next), error: None }
}

///|
fn overlay_status(overlay : OverlayPanel) -> String {
  match overlay {
    OverlayClosed => "Panels hidden."
    EditorOverlay => "Edit panel open."
    TraceOverlay => "Trace inspector open."
    SnapshotOverlay => "Snapshot inspector open."
  }
}

///|
fn appearance_label(appearance : Appearance) -> String {
  match appearance {
    Paper => "paper"
    Night => "night"
  }
}

///|
fn grid_column_count() -> Int {
  50
}

///|
fn grid_row_count() -> Int {
  50
}

///|
fn column_labels() -> Array[String] {
  [
    "A", "B", "C", "D", "E", "F", "G", "H", "I", "J", "K", "L", "M", "N", "O", "P",
    "Q", "R", "S", "T", "U", "V", "W", "X", "Y", "Z", "AA", "AB", "AC", "AD", "AE",
    "AF", "AG", "AH", "AI", "AJ", "AK", "AL", "AM", "AN", "AO", "AP", "AQ", "AR",
    "AS", "AT", "AU", "AV", "AW", "AX",
  ]
}

///|
fn grid_cells() -> Array[String] {
  let cells = []
  for row in 1..<=grid_row_count() {
    for column in column_labels() {
      cells.push("\{column}\{row}")
    }
  }
  cells
}

///|
fn apply_inline_edit(model : Model, cell : String) -> Model {
  match model.editing_cell {
    Some(editing) =>
      if editing == cell {
        apply_text_edit(model, cell, draft_for(model, cell))
      } else {
        model
      }
    None => model
  }
}

///|
fn cancel_selected(model : Model) -> Model {
  let cell = model.selected_cell
  {
    ..model,
    drafts: update_draft(model.drafts, cell, committed_for(model, cell)),
    status: "Reverted draft for \{cell}.",
    error: None,
    editing_cell: None,
  }
}

///|
fn apply_text_edit(model : Model, cell : String, text : String) -> Model {
  let trimmed = text.trim()
  let id = cell_id(model, cell)
  match @demo.parse_cell_text_op(id, trimmed.to_owned()) {
    Ok(operation) => {
      let next = apply_operation(model, operation, "\{cell} ← \{trimmed}")
      let committed_text = trimmed.to_owned()
      {
        ..next,
        drafts: update_draft(next.drafts, cell, committed_text),
        committed: update_draft(next.committed, cell, committed_text),
        editing_cell: None,
      }
    }
    Err(error) =>
      {
        ..model,
        selected_cell: cell,
        error: Some(format_parse_error(error)),
        status: "Edit not applied.",
        overlay: EditorOverlay,
      }
  }
}

///|
fn delete_selected(model : Model) -> Model {
  let cell = model.selected_cell
  let id = cell_id(model, cell)
  let next = apply_operation(model, @demo.SheetOp::Delete(id), "delete \{cell}")
  {
    ..next,
    drafts: update_draft(next.drafts, cell, ""),
    committed: update_draft(next.committed, cell, ""),
    editing_cell: None,
  }
}

///|
fn apply_operation(
  model : Model,
  operation : @demo.SheetOp,
  edit_label : String,
) -> Model {
  let result = @demo.run_op(
    model.sheet,
    operation,
    capture=visible_cell_ids(model),
  )
  let outcome = friendly_outcome(@demo.format_outcome(result.outcome))
  {
    ..model,
    last_step: Some(result),
    last_edit: edit_label,
    status: "Applied \{edit_label}: \{outcome}.",
    error: None,
  }
}

///|
fn visible_cell_ids(model : Model) -> Array[@typed_spreadsheet.CellId] {
  model.cells.map(cell => cell_id(model, cell))
}

///|
fn cell_id(model : Model, cell : String) -> @typed_spreadsheet.CellId {
  @typed_spreadsheet.CellId::of(model.sheet.sheet_id(), cell)
}

///|
fn draft_for(model : Model, cell : String) -> String {
  draft_text_from(model.drafts, cell)
}

///|
fn committed_for(model : Model, cell : String) -> String {
  draft_text_from(model.committed, cell)
}

///|
fn draft_text_from(drafts : Array[CellDraft], cell : String) -> String {
  match drafts.search_by(draft => draft.cell == cell) {
    Some(index) => drafts[index].text
    None => ""
  }
}

///|
fn draft_is_dirty(model : Model, cell : String) -> Bool {
  draft_for(model, cell) != committed_for(model, cell)
}

///|
fn update_draft(
  drafts : Array[CellDraft],
  cell : String,
  text : String,
) -> Array[CellDraft] {
  match drafts.search_by(draft => draft.cell == cell) {
    Some(_) =>
      drafts.map(draft => {
        if draft.cell == cell {
          { ..draft, text, }
        } else {
          draft
        }
      })
    None => {
      let appended = drafts.copy()
      appended.push({ cell, text })
      appended
    }
  }
}

///|
fn format_parse_error(error : @demo.FormulaTextParseError) -> String {
  match error {
    EmptyInput =>
      "Enter an integer, a formula, or use Delete to clear the cell."
    InvalidInteger(value) => "Could not read \{value} as an integer."
    InvalidCellReference(value) => "\{value} is not a supported cell reference."
    UnsupportedFormula(value) =>
      "Unsupported formula \{value}. Try =A1, =A1 + 1, =A1 * 2, or =if(A1 > 10, 1, 0)."
  }
}
