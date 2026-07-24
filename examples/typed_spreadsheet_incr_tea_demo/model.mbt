///|
struct CellDraft {
  cell : String
  text : String
} derive(Eq, Debug)

///|

///|
struct TraceData {
  outcome : String
  recomputed : Array[String]
  changed : Array[String]
  unchanged : Array[String]
  recomputed_str : String
  changed_str : String
  unchanged_str : String
  snapshot_count : Int
} derive(Eq)

///|
struct EvidenceCellData {
  id : String
  classification : String
  before_kind : String
  before_result_status : String
  before_result : String
  after_kind : String
  after_result_status : String
  after_result : String
} derive(Eq)

///|
struct EvidenceData {
  edit : String
  outcome : String
  cells : Array[EvidenceCellData]
} derive(Eq)

///|
struct Model {
  _marker : Unit
}

///|
struct SheetState {
  _scope : @incr.Scope
  adapter : @egw_adapter.EgwAdapter
  cells : @incr.InputField[Array[String]]
  drafts : @incr.InputField[Array[CellDraft]]
  committed : @incr.InputField[Array[CellDraft]]
  selected_cell : @incr.InputField[String]
  editing_cell : @incr.InputField[String?]
  status : @incr.InputField[String]
  error : @incr.InputField[String?]
  trace : @incr.InputField[TraceData?]
  evidence : @incr.InputField[EvidenceData?]
  last_edit : @incr.InputField[String]
  mut publish_sync : ((@container.SyncMessage) -> Unit)?
  collab_mode : Bool
}

///|
fn SheetState::new(
  runtime : @incr.Runtime,
  mode : SheetStartMode,
) -> SheetState raise @container.DocumentError {
  let scope = @incr.Scope::new(runtime)
  let cells = scope.input_field(grid_cells(), label="typed-sheet.cells")
  let seed_drafts : Array[CellDraft] = [
    { cell: "A1", text: "10" },
    { cell: "B1", text: "=A1 + 1" },
  ]
  let drafts = scope.input_field(seed_drafts.copy(), label="typed-sheet.drafts")
  let committed = scope.input_field(
    seed_drafts.copy(),
    label="typed-sheet.committed",
  )
  let selected_cell = scope.input_field("B1", label="typed-sheet.selected-cell")
  let editing_cell = scope.input_field(None, label="typed-sheet.editing-cell")
  let status = scope.input_field(
    "Ready. This incr_tea proof is separate from the live Rabbita demo.",
    label="typed-sheet.status",
  )
  let error = scope.input_field(None, label="typed-sheet.error")
  let trace = scope.input_field(None, label="typed-sheet.trace")
  let evidence = scope.input_field(None, label="typed-sheet.evidence")
  let last_edit = scope.input_field("Seed sheet", label="typed-sheet.last-edit")
  let collab_mode = match mode {
    SheetStartMode::Standalone => false
    SheetStartMode::Host(_, _) | SheetStartMode::Join(_, _) => true
  }

  // Allocate a distinct local authority incarnation until transport owns room identity.
  let mut reset_counter = 0
  let reset_factory = (_generation : DocumentGeneration) => {
    reset_counter += 1
    let replica_id = "typed-sheet-replica-\{reset_counter}"
    let document = @container.Document::new(replica_id)
    let node = document.create_node(parent=@container.root_id)
    @egw_adapter.ResetAuthority::ResetAuthority(
      @core.CollaborativeSheetId::CollaborativeSheetId(
        "typed-sheet-document-\{reset_counter}",
      ),
      document,
      node,
      @typed_spreadsheet.SheetId(reset_counter + 1),
    )
  }
  let bindings = @egw_adapter.ProjectionBindings::ProjectionBindings(
    () => {
      ReadOnlyArray::from_array(
        drafts
        .peek()
        .map(draft => {
          @core.DraftObservation::DraftObservation(draft.cell, draft.text)
        }),
      )
    },
    decision => {
      match decision {
        @core.ProjectionDecision::SetCommitted(address, text) => {
          let value = match text {
            Some(text) => text
            None => ""
          }
          committed.set(update_draft(committed.peek(), address, value))
        }
        @core.ProjectionDecision::SetDraft(address, text) => {
          let value = match text {
            Some(text) => text
            None => ""
          }
          drafts.set(update_draft(drafts.peek(), address, value))
        }
        @core.ProjectionDecision::SetDiagnostic(address, diagnostic) =>
          match diagnostic {
            Some(value) =>
              error.set(
                Some("Projection diagnostic at \{address}: \{repr(value)}"),
              )
            None => error.set(None)
          }
        @core.ProjectionDecision::ApplyWorksheet(_) => ()
      }
    },
  )
  let seeds = [
    @egw_adapter.Seed::Seed("A1", @core.CellRegister::Source("10")),
    @egw_adapter.Seed::Seed("B1", @core.CellRegister::Source("=A1 + 1")),
  ]
  let started = try {
    match mode {
      SheetStartMode::Standalone =>
        @egw_adapter.EgwAdapter::bootstrap(
          runtime,
          "typed-sheet-replica-0",
          @core.CollaborativeSheetId::CollaborativeSheetId(
            "typed-sheet-document-0",
          ),
          @typed_spreadsheet.SheetId(1),
          seeds,
          bindings,
          reset_factory,
        )
      SheetStartMode::Host(room, replica) =>
        @egw_adapter.EgwAdapter::bootstrap(
          runtime,
          replica.0,
          @core.CollaborativeSheetId::CollaborativeSheetId(room),
          @typed_spreadsheet.SheetId(1),
          seeds,
          bindings,
          reset_factory,
        )
      SheetStartMode::Join(payload, document) =>
        @egw_adapter.EgwAdapter::attach(
          runtime,
          payload.identity,
          payload.sheet_id,
          payload.generation,
          document,
          payload.node,
          seeds,
          bindings,
          reset_factory,
        )
    }
  } catch {
    error => {
      scope.dispose()
      raise error
    }
  }
  let adapter = match started {
    @egw_adapter.AdapterStartResult::Ready(adapter, _) => adapter
    @egw_adapter.AdapterStartResult::Failed(error) => {
      scope.dispose()
      raise @container.DocumentError::Internal(
        detail="typed sheet bootstrap failed: \{repr(error)}",
      )
    }
  }
  {
    _scope: scope,
    adapter,
    cells,
    drafts,
    committed,
    selected_cell,
    editing_cell,
    status,
    error,
    trace,
    evidence,
    last_edit,
    publish_sync: None,
    collab_mode,
  }
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
fn cell_id_from_sheet(
  adapter : @egw_adapter.EgwAdapter,
  cell : String,
) -> @typed_spreadsheet.CellId {
  @typed_spreadsheet.CellId::of(adapter.sheet_id(), cell)
}

///|
fn state_visible_cell_ids(
  state : Ref[SheetState],
) -> Array[@typed_spreadsheet.CellId] {
  state.val.cells
  .peek()
  .map(cell => cell_id_from_sheet(state.val.adapter, cell))
}

///|
fn evidence_capture_limit() -> Int {
  16
}

///|
fn state_capture_cell_ids(
  state : Ref[SheetState],
  target : @typed_spreadsheet.CellId,
) -> Array[@typed_spreadsheet.CellId] {
  let limit = evidence_capture_limit()
  let ids = [target]
  let selected = state_cell_id(state, state.val.selected_cell.peek())
  if selected != target && ids.length() < limit {
    ids.push(selected)
  }
  let cells = state.val.cells.peek()
  let mut index = 0
  while index < cells.length() && ids.length() < limit {
    let cell = cells[index]
    let id = cell_id_from_sheet(state.val.adapter, cell)
    if id != target && !ids.contains(id) {
      let snapshot = state.val.adapter.inspect_cell(cell)
      if snapshot.static_references.contains(target) {
        ids.push(id)
      }
    }
    index += 1
  }
  ids
}

///|
fn state_cell_id(
  state : Ref[SheetState],
  cell : String,
) -> @typed_spreadsheet.CellId {
  cell_id_from_sheet(state.val.adapter, cell)
}

///|
fn draft_text_from(drafts : ArrayView[CellDraft], cell : String) -> String {
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
  @tea.Cmd::none()
}

///|
fn use_example(state : Ref[SheetState], text : String) -> @tea.Cmd[Msg] {
  let s = state.val
  let cell = s.selected_cell.peek()
  let current_drafts = s.drafts.peek()
  s.drafts.set(update_draft(current_drafts, cell, text))
  s.error.set(None)
  @tea.Cmd::none()
}

///|
fn update_draft_for_cell(
  state : Ref[SheetState],
  cell : String,
  text : String,
) -> @tea.Cmd[Msg] {
  let s = state.val
  s.selected_cell.set(cell)
  let current_drafts = s.drafts.peek()
  s.drafts.set(update_draft(current_drafts, cell, text))
  s.error.set(None)
  @tea.Cmd::none()
}

///|
fn move_selection(
  state : Ref[SheetState],
  delta_col : Int,
  delta_row : Int,
) -> @tea.Cmd[Msg] {
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

// ── Edit operations: execute after the update batch commits ─────────

///|
fn sheet_planning_context(state : Ref[SheetState]) -> SheetPlanningContext {
  let s = state.val
  let sheet_id = s.adapter.sheet_id()
  {
    sheet_id,
    selected_cell: @typed_spreadsheet.CellId::of(
      sheet_id,
      s.selected_cell.peek(),
    ),
    editing_cell: s.editing_cell
    .peek()
    .map(cell => @typed_spreadsheet.CellId::of(sheet_id, cell)),
    drafts: ReadOnlyArray::from_array(s.drafts.peek()),
    generation: s.adapter.generation(),
  }
}

///|
fn sheet_execution_context(state : Ref[SheetState]) -> SheetExecutionContext {
  let s = state.val
  let sheet_id = s.adapter.sheet_id()
  SheetExecutionContext::SheetExecutionContext(
    @typed_spreadsheet.CellId::of(sheet_id, s.selected_cell.peek()),
    s.editing_cell
    .peek()
    .map(cell => @typed_spreadsheet.CellId::of(sheet_id, cell)),
    s.adapter.generation(),
  )
}

///|
fn execute_sheet_command(
  _runtime : @incr.Runtime,
  state : Ref[SheetState],
  command : SheetCommand,
) -> CommandApplicability {
  execute_adapter_command(state, command)
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
fn cell_snapshot_text(snapshot : @typed_spreadsheet.CellSnapshot) -> String {
  if snapshot.present {
    cell_result_text(snapshot.result)
  } else {
    ""
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
