///|
struct CellDraft {
  cell : String
  text : String
} derive(Eq)

///|
///|
struct TraceData {
  recomputed_str : String
  changed_str : String
  unchanged_str : String
  snapshot_count : Int
} derive(Eq)

struct SheetState {
  scope : @incr.Scope
  sheet : @typed_spreadsheet.Worksheet
  cells : @incr.InputField[Array[String]]
  drafts : @incr.InputField[Array[CellDraft]]
  committed : @incr.InputField[Array[CellDraft]]
  selected_cell : @incr.InputField[String]
  editing_cell : @incr.InputField[String?]
  status : @incr.InputField[String]
  error : @incr.InputField[String?]
  trace : @incr.InputField[TraceData?]
  last_edit : @incr.InputField[String]
}

///|
fn SheetState::new(runtime : @incr.Runtime) -> SheetState {
  let scope = @incr.Scope::new(runtime)
  let sheet = @typed_spreadsheet.Worksheet(runtime, @typed_spreadsheet.SheetId(1))
  let cells = scope.input_field(grid_cells(), label="typed-sheet.cells")
  let seed_drafts = [
    { cell: "A1", text: "10" },
    { cell: "B1", text: "=A1 + 1" },
  ]
  let drafts = scope.input_field(seed_drafts, label="typed-sheet.drafts")
  let committed = scope.input_field(seed_drafts, label="typed-sheet.committed")
  let selected_cell = scope.input_field("B1", label="typed-sheet.selected-cell")
  let editing_cell = scope.input_field(None, label="typed-sheet.editing-cell")
  let status = scope.input_field(
    "Ready. This incr_tea proof is separate from the live Rabbita demo.",
    label="typed-sheet.status",
  )
  let error = scope.input_field(None, label="typed-sheet.error")
  let trace = scope.input_field(None, label="typed-sheet.trace")
  let last_edit = scope.input_field("Seed sheet", label="typed-sheet.last-edit")
  let state = {
    scope,
    sheet,
    cells,
    drafts,
    committed,
    selected_cell,
    editing_cell,
    status,
    error,
    trace,
    last_edit,
  }
  // Seed worksheet with A1=10, B1=formula — then reset meta state to clean
  let state_ref = Ref(state)
  seed_text_edit(state_ref, "A1", "10")
  seed_text_edit(state_ref, "B1", "=A1 + 1")
  let s = state_ref.val
  s.trace.set(None)
  s.last_edit.set("Seed sheet")
  s.status.set("Ready. This incr_tea proof is separate from the live Rabbita demo.")
  s.error.set(None)
  state_ref.val
}

///| Constructs a `Model` snapshot from current InputField values.
fn SheetState::read_model(self : SheetState) -> Model {
  {
    sheet: self.sheet,
    cells: self.cells.get(),
    drafts: self.drafts.get(),
    committed: self.committed.get(),
    selected_cell: self.selected_cell.get(),
    editing_cell: self.editing_cell.get(),
    status: self.status.get(),
    error: self.error.get(),
    trace_data: self.trace.get(),
    last_edit: self.last_edit.get(),
  }
}

///| Test-only snapshot using `peek()` — no reactive dependency recorded.
fn SheetState::peek_model(self : SheetState) -> Model {
  {
    sheet: self.sheet,
    cells: self.cells.peek(),
    drafts: self.drafts.peek(),
    committed: self.committed.peek(),
    selected_cell: self.selected_cell.peek(),
    editing_cell: self.editing_cell.peek(),
    status: self.status.peek(),
    error: self.error.peek(),
    trace_data: self.trace.peek(),
    last_edit: self.last_edit.peek(),
  }
}
///| Snapshot struct for view functions and test assertions.
///| The view uses `SheetState::read_model` to construct this; handlers
///| update `InputField`s directly without constructing a `Model`.
struct Model {
  sheet : @typed_spreadsheet.Worksheet
  cells : Array[String]
  drafts : Array[CellDraft]
  committed : Array[CellDraft]
  selected_cell : String
  editing_cell : String?
  trace_data : TraceData?
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

// ── Pure handler helpers (no InputField dependency) ────────────────

///|
fn cell_id_from_sheet(sheet : @typed_spreadsheet.Worksheet, cell : String) -> @typed_spreadsheet.CellId {
  @typed_spreadsheet.CellId::of(sheet.sheet_id(), cell)
}

///|
fn state_visible_cell_ids(state : Ref[SheetState]) -> Array[@typed_spreadsheet.CellId] {
  state.val.cells.peek().map(cell => cell_id_from_sheet(state.val.sheet, cell))
}

///|
fn state_cell_id(state : Ref[SheetState], cell : String) -> @typed_spreadsheet.CellId {
  cell_id_from_sheet(state.val.sheet, cell)
}

///|
fn draft_text_from(drafts : Array[CellDraft], cell : String) -> String {
  match drafts.search_by(draft => draft.cell == cell) {
    Some(index) => drafts[index].text
    None => ""
  }
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

// ── Handlers: mutate InputFields directly ─────────────────────────

///|
fn select_cell(state : Ref[SheetState], cell : String) -> @tea.Cmd[Msg] {
  let s = state.val
  s.selected_cell.set(cell)
  s.editing_cell.set(None)
  s.status.set("Selected \{cell}.")
  s.error.set(None)
  @tea.Cmd::none()
}

///|
fn begin_inline_edit(state : Ref[SheetState], cell : String) -> @tea.Cmd[Msg] {
  let s = state.val
  s.selected_cell.set(cell)
  s.editing_cell.set(Some(cell))
  s.status.set("Editing \{cell} inline.")
  s.error.set(None)
  @tea.Cmd::focus_element_by_id(inline_editor_id(cell), select=true)
}

///|
fn use_example(state : Ref[SheetState], text : String) -> @tea.Cmd[Msg] {
  let s = state.val
  let cell = s.selected_cell.peek()
  let current_drafts = s.drafts.peek()
  s.drafts.set(update_draft(current_drafts, cell, text))
  s.status.set("Loaded example text for \{cell}.")
  s.error.set(None)
  @tea.Cmd::none()
}

///|
fn update_draft_for_cell(state : Ref[SheetState], cell : String, text : String) -> @tea.Cmd[Msg] {
  let s = state.val
  s.selected_cell.set(cell)
  let current_drafts = s.drafts.peek()
  s.drafts.set(update_draft(current_drafts, cell, text))
  s.status.set("Drafting \{cell}.")
  s.error.set(None)
  @tea.Cmd::none()
}

///|
fn move_selection(state : Ref[SheetState], delta_col : Int, delta_row : Int) -> @tea.Cmd[Msg] {
  let s = state.val
  if s.editing_cell.peek() is Some(_) {
    return @tea.Cmd::none()
  }
  let cells = s.cells.peek()
  let current_selected = s.selected_cell.peek()
  guard cells.search_by(cell => cell == current_selected) is Some(index) else {
    return @tea.Cmd::none()
  }
  let col_count = grid_column_count()
  let row_count = grid_row_count()
  guard row_count != 0 else { return @tea.Cmd::none() }
  let row = index / col_count
  let col = index % col_count
  let next_row = (row + delta_row).clamp(min=0, max=row_count - 1)
  let next_col = (col + delta_col).clamp(min=0, max=col_count - 1)
  let next_index = next_row * col_count + next_col
  guard next_index >= 0 && next_index < cells.length() else {
    return @tea.Cmd::none()
  }
  let next_cell = cells[next_index]
  guard next_cell != current_selected else { return @tea.Cmd::none() }
  s.selected_cell.set(next_cell)
  s.editing_cell.set(None)
  s.status.set("Selected \{next_cell}.")
  s.error.set(None)
  @tea.Cmd::none()
}

///|
fn cancel_selected(state : Ref[SheetState]) -> @tea.Cmd[Msg] {
  let s = state.val
  let cell = s.selected_cell.peek()
  let current_drafts = s.drafts.peek()
  let committed_text = draft_text_from(s.committed.peek(), cell)
  s.drafts.set(update_draft(current_drafts, cell, committed_text))
  s.status.set("Reverted draft for \{cell}.")
  s.error.set(None)
  s.editing_cell.set(None)
  @tea.Cmd::none()
}

// ── Edit handlers: run as Cmd::effect to observe committed worksheet ─

///|
fn apply_text_edit(state : Ref[SheetState], cell : String, text : String) -> Unit {
  let trimmed = text.trim()
  let id = state_cell_id(state, cell)
  match @demo.parse_cell_text_op(id, trimmed.to_owned()) {
    Ok(operation) => {
      let s = state.val
      let result = @demo.run_batched_op(
        s.sheet,
        operation,
        capture=[state_cell_id(state, s.selected_cell.peek())],
        trace_cells=state_visible_cell_ids(state),
      )
      let outcome = @demo.format_outcome(result.outcome)
      let committed_text = trimmed.to_owned()
      let current_drafts = s.drafts.peek()
      let current_committed = s.committed.peek()
      s.trace.set(
        Some(
          {
            recomputed_str: @demo.format_cell_ids(result.trace.recomputed),
            changed_str: @demo.format_cell_ids(result.trace.changed),
            unchanged_str: @demo.format_cell_ids(result.trace.unchanged),
            snapshot_count: result.cell_snapshots.length(),
          },
        ),
      )
      s.last_edit.set("\{cell} ← \{trimmed}")
      s.status.set("Applied \{cell} ← \{trimmed}: \{outcome}.")
      s.error.set(None)
      s.selected_cell.set(cell)
      s.drafts.set(update_draft(current_drafts, cell, committed_text))
      s.committed.set(update_draft(current_committed, cell, committed_text))
      s.editing_cell.set(None)
    }
    Err(EmptyInput) => {
      let s = state.val
      let current_drafts = s.drafts.peek()
      let committed_text = draft_text_from(s.committed.peek(), cell)
      s.selected_cell.set(cell)
      s.drafts.set(update_draft(current_drafts, cell, committed_text))
      s.status.set("Left \{cell} unchanged.")
      s.error.set(None)
      s.editing_cell.set(None)
    }
    Err(error) => {
      let s = state.val
      s.selected_cell.set(cell)
      s.error.set(Some(format_parse_error(error)))
      s.status.set("Edit not applied.")
      s.editing_cell.set(None)
    }
  }
}

///| Seeds a worksheet cell during construction or reset.
///| Like `apply_text_edit` but does NOT touch meta-fields (last_step, last_edit,
///| status, selected_cell, editing_cell) — the caller manages those.
fn seed_text_edit(state : Ref[SheetState], cell : String, text : String) -> Unit {
  let trimmed = text.trim()
  let id = state_cell_id(state, cell)
  match @demo.parse_cell_text_op(id, trimmed.to_owned()) {
    Ok(operation) => {
      let s = state.val
      ignore(@demo.run_batched_op(
        s.sheet,
        operation,
        capture=[id],
        trace_cells=state_visible_cell_ids(state),
      ))
      let committed_text = trimmed.to_owned()
      let current_drafts = s.drafts.peek()
      let current_committed = s.committed.peek()
      s.drafts.set(update_draft(current_drafts, cell, committed_text))
      s.committed.set(update_draft(current_committed, cell, committed_text))
    }
    _ => ()
  }
}

///|
fn apply_selected_cmd(state : Ref[SheetState]) -> @tea.Cmd[Msg] {
  let cell = state.val.selected_cell.peek()
  @tea.Cmd::effect(_ => {
    if state.val.selected_cell.peek() == cell {
      apply_text_edit(state, cell, draft_text_from(state.val.drafts.peek(), cell))
    }
  })
}

///|
fn apply_inline_edit_cmd(state : Ref[SheetState], cell : String) -> @tea.Cmd[Msg] {
  @tea.Cmd::effect(_ => {
    if state.val.editing_cell.peek() == Some(cell) {
      apply_text_edit(state, cell, draft_text_from(state.val.drafts.peek(), cell))
    }
  })
}

///|
fn delete_selected_cmd(state : Ref[SheetState]) -> @tea.Cmd[Msg] {
  let cell = state.val.selected_cell.peek()
  @tea.Cmd::effect(_ => {
    if state.val.selected_cell.peek() == cell {
      let s = state.val
      let id = state_cell_id(state, cell)
      let result = @demo.run_batched_op(
        s.sheet,
        @demo.SheetOp::Delete(id),
        capture=[id],
        trace_cells=state_visible_cell_ids(state),
      )
      let outcome = @demo.format_outcome(result.outcome)
      let current_drafts = s.drafts.peek()
      let current_committed = s.committed.peek()
      s.trace.set(
        Some(
          {
            recomputed_str: @demo.format_cell_ids(result.trace.recomputed),
            changed_str: @demo.format_cell_ids(result.trace.changed),
            unchanged_str: @demo.format_cell_ids(result.trace.unchanged),
            snapshot_count: result.cell_snapshots.length(),
          },
        ),
      )
      s.last_edit.set("delete \{cell}")
      s.status.set("Applied delete \{cell}: \{outcome}.")
      s.error.set(None)
      s.drafts.set(update_draft(current_drafts, cell, ""))
      s.committed.set(update_draft(current_committed, cell, ""))
      s.editing_cell.set(None)
    }
  })
}

///|
fn reset_sheet_cmd(runtime : @incr.Runtime, state : Ref[SheetState]) -> @tea.Cmd[Msg] {
  @tea.Cmd::effect(_ => {
    let s = state.val
    s.sheet.dispose()
    let new_sheet = @typed_spreadsheet.Worksheet(
      runtime,
      @typed_spreadsheet.SheetId(1),
    )
    let seed_drafts = [
      { cell: "A1", text: "10" },
      { cell: "B1", text: "=A1 + 1" },
    ]
    s.cells.set(grid_cells())
    s.drafts.set(seed_drafts)
    s.committed.set(seed_drafts)
    s.selected_cell.set("B1")
    s.editing_cell.set(None)
    s.trace.set(None)
    s.last_edit.set("Seed sheet")
    s.status.set("Ready. This incr_tea proof is separate from the live Rabbita demo.")
    s.error.set(None)
    // Write back — SheetState has value semantics; InputField handles in the
    // copy share the same reactive cells, but `sheet` needs explicit replacement
    // so the Ref carries the new worksheet.
    state.val = { ..s, sheet: new_sheet }
    // Seed initial cell values — reads from state.val which now has the new sheet
    seed_text_edit(state, "A1", "10")
    seed_text_edit(state, "B1", "=A1 + 1")
  })
}

// ── View helpers (pure, from Model snapshot) ───────────────────────

///|
fn draft_for(model : Model, cell : String) -> String {
  draft_text_from(model.drafts, cell)
}

///|
fn committed_for(model : Model, cell : String) -> String {
  draft_text_from(model.committed, cell)
}

///|
fn draft_is_dirty(model : Model, cell : String) -> Bool {
  draft_for(model, cell) != committed_for(model, cell)
}

///|
fn cell_id(model : Model, cell : String) -> @typed_spreadsheet.CellId {
  cell_id_from_sheet(model.sheet, cell)
}


// ── Grid constants ─────────────────────────────────────────────────

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

// ── Cell display helpers (pure) ────────────────────────────────────

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

