///|
struct TypedSheetApp {
  prog_grid : @tea.Program[Msg, @tea.Html[Msg]]
  prog_formula : @tea.Program[Msg, @tea.Html[Msg]]
  prog_status : @tea.Program[Msg, @tea.Html[Msg]]
  prog_trace : @tea.Program[Msg, @tea.Html[Msg]]
  _state : Ref[SheetState]
  _model_marker : Model
}

///|
fn TypedSheetApp::TypedSheetApp(runtime : @incr.Runtime) -> TypedSheetApp {
  let state = Ref(SheetState::new(runtime))
  let update : (Msg) -> @tea.Cmd[Msg] = msg => handle_msg(runtime, state, msg)
  // Shared update; each program gets its own scope for the view Derived +
  // Watch. Disposing any one program only tears down its view tracking, not
  // the shared InputFields owned by `state.val._scope`.
  let prog_grid = @tea.Program::Program(
    runtime,
    @incr.Scope::new(runtime),
    update,
    fn() { state_grid(state.val) },
    label="typed-sheet.grid",
  )
  let prog_formula = @tea.Program::Program(
    runtime,
    @incr.Scope::new(runtime),
    update,
    fn() { state_formula_bar(state.val) },
    label="typed-sheet.formula-bar",
  )
  let prog_status = @tea.Program::Program(
    runtime,
    @incr.Scope::new(runtime),
    update,
    fn() { state_status(state.val) },
    label="typed-sheet.status",
  )
  let prog_trace = @tea.Program::Program(
    runtime,
    @incr.Scope::new(runtime),
    update,
    fn() { state_trace(state.val) },
    label="typed-sheet.trace",
  )
  {
    prog_grid,
    prog_formula,
    prog_status,
    prog_trace,
    _state: state,
    _model_marker: { _marker: () },
  }
}

///|
fn handle_msg(
  runtime : @incr.Runtime,
  state : Ref[SheetState],
  msg : Msg,
) -> @tea.Cmd[Msg] {
  match msg {
    SelectCell(cell) => select_cell(state, cell)
    UpdateDraft(cell, text) => update_draft_for_cell(state, cell, text)
    UseExample(text) => use_example(state, text)
    ApplySelected => apply_selected_cmd(state)
    DeleteSelected => delete_selected_cmd(state)
    ResetSheet => reset_sheet_cmd(runtime, state)
    CancelSelected => cancel_selected(state)
    BeginInlineEdit(cell) => begin_inline_edit(state, cell)
    BeginSelectedInlineEdit =>
      begin_inline_edit(state, state.val.selected_cell.peek())
    ApplyInlineEdit(cell) => apply_inline_edit_cmd(state, cell)
    MoveSelection(delta_col, delta_row) =>
      move_selection(state, delta_col, delta_row)
  }
}

// ── Event configuration (stays shared across all roots) ───────────

///|
struct KeyResolution {
  message : Msg
  prevent_default : Bool
  stop_propagation : Bool
}

///|
fn key_resolution(message : Msg) -> KeyResolution {
  { message, prevent_default: true, stop_propagation: true }
}

///|
fn resolve_text_input(
  id : @tea.TextInputId,
  payload : @tea.TextInputPayload,
) -> Msg? {
  match id.name.strip_prefix("draft:") {
    Some(cell) => Some(UpdateDraft(cell.to_owned(), payload.value))
    None => None
  }
}

///|
fn resolve_key_action(
  id : @tea.KeyEventId,
  payload : @tea.KeyPayload,
) -> KeyResolution? {
  if payload.alt_key || payload.ctrl_key || payload.meta_key {
    return None
  }
  match id.name {
    "grid" => resolve_grid_key(payload)
    [.. "inline:", .. cell] => resolve_inline_key(cell, payload)
    "formula" => resolve_formula_key(payload)
    _ => None
  }
}

///|
fn resolve_key_event(
  id : @tea.KeyEventId,
  payload : @tea.KeyPayload,
) -> @tea.KeyEventDispatch[Msg]? {
  match resolve_key_action(id, payload) {
    Some(action) =>
      Some(
        @tea.KeyEventDispatch::message(
          action.message,
          prevent_default=action.prevent_default,
          stop_propagation=action.stop_propagation,
        ),
      )
    None => None
  }
}

///|
fn resolve_grid_key(payload : @tea.KeyPayload) -> KeyResolution? {
  let message = match payload.key {
    "ArrowLeft" => Some(MoveSelection(-1, 0))
    "ArrowRight" => Some(MoveSelection(1, 0))
    "ArrowUp" => Some(MoveSelection(0, -1))
    "ArrowDown" => Some(MoveSelection(0, 1))
    "Enter" => Some(BeginSelectedInlineEdit)
    "Escape" => Some(CancelSelected)
    _ => None
  }
  match message {
    Some(message) => Some(key_resolution(message))
    None => None
  }
}

///|
fn resolve_inline_key(
  cell : StringView,
  payload : @tea.KeyPayload,
) -> KeyResolution? {
  let message = match payload.key {
    "Enter" => Some(ApplyInlineEdit(cell.to_owned()))
    "Escape" => Some(CancelSelected)
    _ => None
  }
  match message {
    Some(message) => Some(key_resolution(message))
    None => None
  }
}

///|
fn resolve_formula_key(payload : @tea.KeyPayload) -> KeyResolution? {
  match payload.key {
    "Escape" => Some(key_resolution(CancelSelected))
    _ => None
  }
}

// ── Id / tag helpers ──────────────────────────────────────────────

///|
fn input_tag(cell : String) -> String {
  "draft:" + cell
}

///|
fn grid_key_id() -> @tea.KeyEventId {
  @tea.KeyEventId("grid")
}

///|
fn inline_key_id(cell : String) -> @tea.KeyEventId {
  @tea.KeyEventId("inline:" + cell)
}

///|
fn formula_key_id() -> @tea.KeyEventId {
  @tea.KeyEventId("formula")
}

///|
fn inline_editor_id(cell : String) -> String {
  "inline-editor-" + cell
}
