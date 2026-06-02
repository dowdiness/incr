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
  grid_snapshot_cache : @hashmap.HashMap[String, GridCellSnapshot]
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
  intro_visible : Bool
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
  MoveSelection(Int, Int)
  HandleAppKey(@html.Keyboard)
  SetAppearance(Appearance)
  SetOverlay(OverlayPanel)
  CloseIntro
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
    grid_snapshot_cache: HashMap([]),
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
    intro_visible: true,
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
    intro_visible: true,
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
    MoveSelection(delta_col, delta_row) =>
      if model.editing_cell is Some(_) {
        model
      } else {
        move_selection(model, delta_col, delta_row)
      }
    HandleAppKey(event) => handle_app_key(model, event)
    SetAppearance(appearance) => set_appearance(model, appearance)
    SetOverlay(overlay) => set_overlay(model, overlay)
    CloseIntro => close_intro(model)
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
  guard model.cells.search_by(cell => cell == model.selected_cell)
    is Some(index) else {
    return model
  }
  let col_count = grid_column_count()
  let row_count = grid_row_count()
  guard row_count != 0 else { return model }
  let row = index / col_count
  let col = index % col_count
  let next_row = (row + delta_row).clamp(min=0, max=row_count - 1)
  let next_col = (col + delta_col).clamp(min=0, max=col_count - 1)
  let next_index = next_row * col_count + next_col
  guard next_index >= 0 && next_index < model.cells.length() else {
    return model
  }
  let next_cell = model.cells[next_index]
  guard next_cell != model.selected_cell else { return model }
  { ..select_cell(model, next_cell), status: "Selected \{next_cell}." }
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
fn close_intro(model : Model) -> Model {
  if model.intro_visible {
    { ..model, intro_visible: false }
  } else {
    model
  }
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
  if model.editing_cell == Some(cell) {
    apply_text_edit(model, cell, draft_for(model, cell))
  } else {
    model
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
    // An empty edit is not a mistake to flag — fail gracefully: revert the
    // draft to the committed text, leave the cell as-is, and keep the overlay
    // state untouched (no error styling, no forced editor pop).
    Err(EmptyInput) =>
      {
        ..model,
        selected_cell: cell,
        drafts: update_draft(model.drafts, cell, committed_for(model, cell)),
        status: "Left \{cell} unchanged.",
        error: None,
        editing_cell: None,
      }
    Err(error) =>
      {
        ..model,
        selected_cell: cell,
        error: Some(format_parse_error(error)),
        status: "Edit not applied.",
        overlay: EditorOverlay,
        editing_cell: None,
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
  // Bounded evidence surface: the operation target and (for formulas) its
  // direct references are captured automatically by `run_op`. We add only the
  // focused cell so the Evidence panel has before/after for what the user is
  // editing — not all ~2,500 grid cells, which hid the incremental boundary.
  let result = @demo.run_op(model.sheet, operation, capture=[
    cell_id(model, model.selected_cell),
  ])
  let outcome = outcome_label(result.outcome)
  {
    ..model,
    grid_snapshot_cache: refresh_grid_snapshot_cache(model, result),
    last_step: Some(result),
    last_edit: edit_label,
    status: "Applied \{edit_label}: \{outcome}.",
    error: None,
  }
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
