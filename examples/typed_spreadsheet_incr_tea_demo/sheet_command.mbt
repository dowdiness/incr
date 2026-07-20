///|
struct DocumentGeneration(Int) derive(Eq, Debug)

///|
fn DocumentGeneration::initial() -> DocumentGeneration {
  DocumentGeneration(0)
}

///|
fn DocumentGeneration::next(self : DocumentGeneration) -> DocumentGeneration {
  DocumentGeneration(self.0 + 1)
}

///|
enum SheetCommand {
  ApplyFromSelection(@typed_spreadsheet.CellId, String, DocumentGeneration)
  ApplyFromEditor(@typed_spreadsheet.CellId, String, DocumentGeneration)
  DeleteFromSelection(@typed_spreadsheet.CellId, DocumentGeneration)
  ResetDocument(DocumentGeneration)
} derive(Eq, Debug)

///|
enum UiEffect {
  FocusInlineEditor(String)
} derive(Eq, Debug)

///|
struct SheetPlan {
  command : SheetCommand?
  ui_effect : UiEffect?
} derive(Eq, Debug)

///|
struct SheetPlanningContext {
  sheet_id : @typed_spreadsheet.SheetId
  selected_cell : @typed_spreadsheet.CellId
  editing_cell : @typed_spreadsheet.CellId?
  drafts : ReadOnlyArray[CellDraft]
  generation : DocumentGeneration
} derive(Eq, Debug)

///|
struct SheetExecutionContext {
  selected_cell : @typed_spreadsheet.CellId
  editing_cell : @typed_spreadsheet.CellId?
  generation : DocumentGeneration
} derive(Eq, Debug)

///|
enum CommandApplicability {
  Applicable
  StaleGeneration
  LocalPreconditionFailed
} derive(Eq, Debug)

///|
fn plan_sheet_command(context : SheetPlanningContext, msg : Msg) -> SheetPlan {
  let none = { command: None, ui_effect: None }
  match msg {
    ApplySelected => {
      let target = context.selected_cell
      {
        command: Some(
          ApplyFromSelection(
            target,
            draft_text_from(
              context.drafts.view(),
              @demo.cell_id_to_string(target),
            ),
            context.generation,
          ),
        ),
        ui_effect: None,
      }
    }
    ApplyInlineEdit(address) => {
      let target = @typed_spreadsheet.CellId::of(context.sheet_id, address)
      {
        command: Some(
          ApplyFromEditor(
            target,
            draft_text_from(context.drafts.view(), address),
            context.generation,
          ),
        ),
        ui_effect: None,
      }
    }
    DeleteSelected => {
      let target = context.selected_cell
      {
        command: Some(DeleteFromSelection(target, context.generation)),
        ui_effect: None,
      }
    }
    ResetSheet =>
      { command: Some(ResetDocument(context.generation)), ui_effect: None }
    BeginInlineEdit(address) =>
      { command: None, ui_effect: Some(FocusInlineEditor(address)) }
    BeginSelectedInlineEdit =>
      {
        command: None,
        ui_effect: Some(
          FocusInlineEditor(@demo.cell_id_to_string(context.selected_cell)),
        ),
      }
    _ => none
  }
}

///|
fn validate_sheet_command(
  command : SheetCommand,
  context : SheetExecutionContext,
) -> CommandApplicability {
  match command {
    ApplyFromSelection(target, _, generation)
    | DeleteFromSelection(target, generation) =>
      if generation != context.generation {
        StaleGeneration
      } else if target != context.selected_cell {
        LocalPreconditionFailed
      } else {
        Applicable
      }
    ApplyFromEditor(target, _, generation) =>
      if generation != context.generation {
        StaleGeneration
      } else if context.editing_cell != Some(target) {
        LocalPreconditionFailed
      } else {
        Applicable
      }
    ResetDocument(generation) =>
      if generation != context.generation {
        StaleGeneration
      } else {
        Applicable
      }
  }
}

///|
fn interpret_sheet_command(
  runtime : @incr.Runtime,
  state : Ref[SheetState],
  plan : SheetPlan,
) -> @tea.Cmd[Msg] {
  let command = match plan.command {
    Some(command) =>
      @tea.Cmd::effect(_ => {
        ignore(execute_sheet_command(runtime, state, command))
      })
    None => @tea.Cmd::none()
  }
  let ui = match plan.ui_effect {
    Some(FocusInlineEditor(address)) =>
      @tea.Cmd::focus_element_by_id(inline_editor_id(address), select=true)
    None => @tea.Cmd::none()
  }
  @tea.Cmd::batch([command, ui])
}
