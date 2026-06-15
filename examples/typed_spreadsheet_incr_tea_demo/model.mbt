///|
struct CellDraft {
  cell : String
  text : String
}

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
  BeginSelectedInlineEdit
  ApplyInlineEdit(String)
  MoveSelection(Int, Int)
} derive(Eq)

///|
fn init_model(runtime : @incr.Runtime) -> Model {
  let sheet = @typed_spreadsheet.Worksheet(
    runtime,
    @typed_spreadsheet.SheetId(1),
  )
  let seed_drafts = [
    { cell: "A1", text: "10" },
    { cell: "B1", text: "=A1 + 1" },
  ]
  let base = {
    sheet,
    cells: grid_cells(),
    drafts: seed_drafts,
    committed: seed_drafts,
    selected_cell: "B1",
    editing_cell: None,
    last_step: None,
    last_edit: "Seed sheet",
    status: "Ready. This incr_tea proof is separate from the live Rabbita demo.",
    error: None,
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
    status: "Ready. This incr_tea proof is separate from the live Rabbita demo.",
    error: None,
  }
}

///|
fn reset_model(model : Model, runtime : @incr.Runtime) -> Model {
  model.sheet.dispose()
  init_model(runtime)
}

///|
fn select_cell(model : Model, cell : String) -> Model {
  {
    ..model,
    selected_cell: cell,
    editing_cell: None,
    status: "Selected \{cell}.",
    error: None,
  }
}

///|
fn begin_inline_edit(model : Model, cell : String) -> Model {
  {
    ..select_cell(model, cell),
    editing_cell: Some(cell),
    status: "Editing \{cell} inline.",
    error: None,
  }
}

///|
fn use_example(model : Model, text : String) -> Model {
  {
    ..model,
    drafts: update_draft(model.drafts, model.selected_cell, text),
    status: "Loaded example text for \{model.selected_cell}.",
    error: None,
  }
}

///|
fn update_draft_for_cell(model : Model, cell : String, text : String) -> Model {
  {
    ..model,
    selected_cell: cell,
    drafts: update_draft(model.drafts, cell, text),
    status: "Drafting \{cell}.",
    error: None,
  }
}

///|
fn move_selection(model : Model, delta_col : Int, delta_row : Int) -> Model {
  if model.editing_cell is Some(_) {
    return model
  }
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
fn apply_inline_edit(model : Model, cell : String) -> Model {
  if model.editing_cell == Some(cell) {
    apply_text_edit(model, cell, draft_for(model, cell))
  } else {
    model
  }
}

///|
fn apply_selected(model : Model) -> Model {
  apply_text_edit(
    model,
    model.selected_cell,
    draft_for(model, model.selected_cell),
  )
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
        selected_cell: cell,
        drafts: update_draft(next.drafts, cell, committed_text),
        committed: update_draft(next.committed, cell, committed_text),
        editing_cell: None,
      }
    }
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
  let result = @demo.run_batched_op(
    model.sheet,
    operation,
    capture=[cell_id(model, model.selected_cell)],
    trace_cells=visible_cell_ids(model),
  )
  let outcome = @demo.format_outcome(result.outcome)
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
    None => [..drafts, { cell, text }]
  }
}

///|
fn grid_column_count() -> Int {
  4
}

///|
fn grid_row_count() -> Int {
  4
}

///|
fn column_labels() -> Array[String] {
  ["A", "B", "C", "D"]
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

///|
fn cell_result_text(result : @typed_spreadsheet.CellResult) -> String {
  match result {
    Ok(value) => cell_value_text(value)
    ParseError(message) => "parse error: \{message}"
    TypeError(message) => "type error: \{message}"
    RefError(message) => "ref error: \{message}"
    CycleError(message) => "cycle: \{message}"
  }
}

///|
fn cell_value_text(value : @typed_spreadsheet.CellValue) -> String {
  match value {
    Int(value) => "\{value}"
    Bool(value) => "\{value}"
    Text(value) => value
    Blank => ""
  }
}

///|
fn cell_result_class(result : @typed_spreadsheet.CellResult) -> String {
  match result {
    Ok(_) => "ok"
    ParseError(_) => "error"
    TypeError(_) => "error"
    RefError(_) => "error"
    CycleError(_) => "error"
  }
}

///|
fn snapshot_kind_text(snapshot : @typed_spreadsheet.CellSnapshot) -> String {
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
