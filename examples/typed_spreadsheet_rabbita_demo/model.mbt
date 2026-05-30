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
  selected_cell : String
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
}

///|
fn init_model() -> Model {
  let sheet = @typed_spreadsheet.Worksheet(
    @incr.Runtime(),
    @typed_spreadsheet.SheetId(1),
  )
  let cells = ["A1", "B1", "A2", "B2"]
  let base = {
    sheet,
    cells,
    drafts: [
      { cell: "A1", text: "10" },
      { cell: "B1", text: "=A1 + 1" },
      { cell: "A2", text: "" },
      { cell: "B2", text: "" },
    ],
    selected_cell: "B1",
    last_step: None,
    last_edit: "Seed sheet",
    status: "Ready.",
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
    last_step: None,
    last_edit: "Seed sheet",
    status: "Ready. Try changing A1 to 15, then apply the edit.",
    error: None,
  }
}

///|
fn update(msg : Msg, model : Model) -> Model {
  match msg {
    SelectCell(cell) =>
      { ..model, selected_cell: cell, status: "Editing \{cell}.", error: None }
    UpdateDraft(cell, text) =>
      {
        ..model,
        selected_cell: cell,
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
  }
}

///|
fn reset_model(model : Model) -> Model {
  model.sheet.dispose()
  init_model()
}

///|
fn apply_text_edit(model : Model, cell : String, text : String) -> Model {
  let trimmed = text.trim()
  let id = cell_id(model, cell)
  match @demo.parse_cell_text_op(id, trimmed.to_owned()) {
    Ok(operation) => apply_operation(model, operation, "\{cell} ← \{trimmed}")
    Err(error) =>
      {
        ..model,
        selected_cell: cell,
        error: Some(format_parse_error(error)),
        status: "Edit not applied.",
      }
  }
}

///|
fn delete_selected(model : Model) -> Model {
  let cell = model.selected_cell
  let id = cell_id(model, cell)
  let next = apply_operation(model, @demo.SheetOp::Delete(id), "delete \{cell}")
  { ..next, drafts: update_draft(next.drafts, cell, "") }
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
  match model.drafts.search_by(draft => draft.cell == cell) {
    Some(index) => model.drafts[index].text
    None => ""
  }
}

///|
fn update_draft(
  drafts : Array[CellDraft],
  cell : String,
  text : String,
) -> Array[CellDraft] {
  let found = Ref(false)
  let next = drafts.map(draft => {
    if draft.cell == cell {
      found.val = true
      { ..draft, text, }
    } else {
      draft
    }
  })
  if found.val {
    next
  } else {
    let appended = next.copy()
    appended.push({ cell, text })
    appended
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
      "Unsupported formula \{value}. Try =A1 + 1, =A1 * 2, or =if(A1 > 10, 1, 0)."
  }
}
