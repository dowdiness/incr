///|
test "incr_tea spreadsheet proof starts with seeded representative grid" {
  let app = TypedSheetApp(@incr.Runtime())
  let model = app._state.val.peek_model()

  inspect(model.selected_cell, content="B1")
  inspect(model.cells.length(), content="16")
  inspect(model.trace_data is None, content="true")
  inspect(draft_for(model, "A1"), content="10")
  inspect(draft_for(model, "B1"), content="=A1 + 1")
  inspect(
    cell_result_text(model.sheet.inspect_cell(cell_id(model, "A1")).result),
    content="10",
  )
  inspect(
    cell_result_text(model.sheet.inspect_cell(cell_id(model, "B1")).result),
    content="11",
  )
  inspect(
    app.prog_grid.read_view_or_abort() == app.prog_grid.read_view_or_abort(),
    content="true",
  )

  app.dispose()
}

///|
test "incr_tea spreadsheet proof applies and cancels through Program dispatch" {
  let app = TypedSheetApp(@incr.Runtime())

  ignore(app.prog_grid.dispatch(BeginInlineEdit("C1")))
  ignore(app.prog_grid.dispatch(UpdateDraft("C1", "7")))
  ignore(app.prog_grid.dispatch(MoveSelection(1, 0)))
  ignore(app.prog_grid.dispatch(ApplyInlineEdit("C1")))
  let applied = app._state.val.peek_model()

  inspect(applied.selected_cell, content="C1")
  inspect(applied.editing_cell is None, content="true")
  inspect(
    cell_result_text(applied.sheet.inspect_cell(cell_id(applied, "C1")).result),
    content="7",
  )
  inspect(applied.last_edit, content="C1 ← 7")

  ignore(app.prog_grid.dispatch(BeginInlineEdit("C1")))
  ignore(app.prog_grid.dispatch(UpdateDraft("C1", "8")))
  ignore(app.prog_grid.dispatch(CancelSelected))
  let cancelled = app._state.val.peek_model()
  inspect(draft_for(cancelled, "C1"), content="7")
  inspect(
    cell_result_text(
      cancelled.sheet.inspect_cell(cell_id(cancelled, "C1")).result,
    ),
    content="7",
  )
  app.dispose()
}

///|
test "incr_tea spreadsheet proof applies formula bar edits and dependent formulas update" {
  let app = TypedSheetApp(@incr.Runtime())

  ignore(app.prog_grid.dispatch(SelectCell("A1")))
  ignore(app.prog_grid.dispatch(UpdateDraft("A1", "15")))
  ignore(app.prog_grid.dispatch(ApplySelected))
  let model = app._state.val.peek_model()

  inspect(model.last_edit, content="A1 ← 15")
  inspect(
    cell_result_text(model.sheet.inspect_cell(cell_id(model, "A1")).result),
    content="15",
  )
  inspect(
    cell_result_text(model.sheet.inspect_cell(cell_id(model, "B1")).result),
    content="16",
  )
  match model.trace_data {
    Some(td) =>
      inspect(td.changed_str, content="[B1]")
    None => abort("expected applied edit")
  }
  app.dispose()
}

///|
test "incr_tea spreadsheet proof maps payload descriptors at renderer boundary" {
  match
    resolve_text_input(
      @tea.TextInputId("draft:A1"),
      @tea.TextInputPayload("15"),
    ) {
    Some(UpdateDraft(cell, text)) => {
      inspect(cell, content="A1")
      inspect(text, content="15")
    }
    _ => abort("expected draft update")
  }

  let enter = @tea.KeyPayload(
    "Enter", "Enter", false, false, false, false, false,
  )
  match resolve_key_action(@tea.KeyEventId("grid"), enter) {
    Some(action) => {
      inspect(action.message == BeginSelectedInlineEdit, content="true")
      inspect(action.prevent_default, content="true")
      inspect(action.stop_propagation, content="true")
    }
    None => abort("expected grid Enter action")
  }

  match resolve_key_action(@tea.KeyEventId("inline:C1"), enter) {
    Some(action) => {
      inspect(action.message == ApplyInlineEdit("C1"), content="true")
      inspect(action.prevent_default, content="true")
      inspect(action.stop_propagation, content="true")
    }
    None => abort("expected inline Enter action")
  }

  let escape = @tea.KeyPayload(
    "Escape", "Escape", false, false, false, false, false,
  )
  match resolve_key_action(@tea.KeyEventId("formula"), escape) {
    Some(action) => inspect(action.message == CancelSelected, content="true")
    None => abort("expected formula Escape action")
  }
}
