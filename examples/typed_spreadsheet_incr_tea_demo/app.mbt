///|
struct TypedSheetApp {
  program : @tea.Program[Msg, @tea.Html[Msg]]
  _state : Ref[Model]
}

///|
fn TypedSheetApp::TypedSheetApp(runtime : @incr.Runtime) -> TypedSheetApp {
  let scope = @incr.Scope::new(runtime)
  let state = Ref(init_model(runtime))
  let version = scope.input_field(0, label="typed-sheet-proof.version")
  let update : (Msg) -> @tea.Cmd[Msg] = msg => {
    handle_msg(runtime, state, version, msg)
  }
  let view : () -> @tea.Html[Msg] raise Failure = () => {
    ignore(version.get())
    view_model(state.val)
  }
  let program = @tea.Program::Program(
    runtime,
    scope,
    update,
    view,
    label="typed-sheet-proof.view",
  )
  { program, _state: state }
}

///|
fn handle_msg(
  runtime : @incr.Runtime,
  state : Ref[Model],
  version : @incr.InputField[Int],
  msg : Msg,
) -> @tea.Cmd[Msg] {
  match msg {
    SelectCell(cell) =>
      update_state(state, version, select_cell(state.val, cell))
    UpdateDraft(cell, text) =>
      update_state(state, version, update_draft_for_cell(state.val, cell, text))
    UseExample(text) =>
      update_state(state, version, use_example(state.val, text))
    ApplySelected => apply_selected_cmd(state, version)
    DeleteSelected => delete_selected_cmd(state, version)
    ResetSheet => reset_sheet_cmd(runtime, state, version)
    CancelSelected => update_state(state, version, cancel_selected(state.val))
    BeginInlineEdit(cell) => focus_inline_edit(state, version, cell)
    BeginSelectedInlineEdit =>
      focus_inline_edit(state, version, state.val.selected_cell)
    ApplyInlineEdit(cell) => apply_inline_edit_cmd(state, version, cell)
    MoveSelection(delta_col, delta_row) =>
      update_state(
        state,
        version,
        move_selection(state.val, delta_col, delta_row),
      )
  }
}

///|
fn update_state(
  state : Ref[Model],
  version : @incr.InputField[Int],
  next : Model,
) -> @tea.Cmd[Msg] {
  replace_state(state, version, next)
  @tea.Cmd::none()
}

///|
fn focus_inline_edit(
  state : Ref[Model],
  version : @incr.InputField[Int],
  cell : String,
) -> @tea.Cmd[Msg] {
  replace_state(state, version, begin_inline_edit(state.val, cell))
  @tea.Cmd::focus_element_by_id(inline_editor_id(cell), select=true)
}

///|
fn replace_state(
  state : Ref[Model],
  version : @incr.InputField[Int],
  next : Model,
) -> Unit {
  state.val = next
  version.set(version.peek() + 1)
}

///|
fn deferred_state_cmd(
  state : Ref[Model],
  version : @incr.InputField[Int],
  next : (Model) -> Model?,
) -> @tea.Cmd[Msg] {
  // Program updates run inside Runtime::batch; the shared operation runner must
  // observe the worksheet after commit, so edit operations run as effects.
  @tea.Cmd::effect(_ => {
    match next(state.val) {
      Some(model) => replace_state(state, version, model)
      None => ()
    }
  })
}

///|
fn apply_selected_cmd(
  state : Ref[Model],
  version : @incr.InputField[Int],
) -> @tea.Cmd[Msg] {
  let cell = state.val.selected_cell
  deferred_state_cmd(state, version, latest => {
    if latest.selected_cell == cell {
      Some(apply_selected(latest))
    } else {
      None
    }
  })
}

///|
fn apply_inline_edit_cmd(
  state : Ref[Model],
  version : @incr.InputField[Int],
  cell : String,
) -> @tea.Cmd[Msg] {
  deferred_state_cmd(state, version, latest => {
    if latest.editing_cell == Some(cell) {
      Some(apply_inline_edit(latest, cell))
    } else {
      None
    }
  })
}

///|
fn delete_selected_cmd(
  state : Ref[Model],
  version : @incr.InputField[Int],
) -> @tea.Cmd[Msg] {
  let cell = state.val.selected_cell
  deferred_state_cmd(state, version, latest => {
    if latest.selected_cell == cell {
      Some(delete_selected(latest))
    } else {
      None
    }
  })
}

///|
fn reset_sheet_cmd(
  runtime : @incr.Runtime,
  state : Ref[Model],
  version : @incr.InputField[Int],
) -> @tea.Cmd[Msg] {
  deferred_state_cmd(state, version, model => Some(reset_model(model, runtime)))
}

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
