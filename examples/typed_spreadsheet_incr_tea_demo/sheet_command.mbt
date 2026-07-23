///|
using @domain {
  type DocumentGeneration,
  type SheetCommand,
  type CommandApplicability,
  type SheetExecutionContext,
  grid_cells,
  grid_column_count,
  grid_row_count,
  column_labels,
}

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
