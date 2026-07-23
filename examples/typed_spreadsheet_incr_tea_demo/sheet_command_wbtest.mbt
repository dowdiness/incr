///|
fn test_sheet_planning_context() -> SheetPlanningContext {
  let sheet_id = @typed_spreadsheet.SheetId(1)
  let selected = @typed_spreadsheet.CellId::of(sheet_id, "B1")
  {
    sheet_id,
    selected_cell: selected,
    editing_cell: Some(@typed_spreadsheet.CellId::of(sheet_id, "C1")),
    drafts: ReadOnlyArray::from_array([
      { cell: "A1", text: "10" },
      { cell: "B1", text: "=A1 + 1" },
      { cell: "C1", text: "7" },
    ]),
    generation: DocumentGeneration::initial(),
  }
}

///|
fn inspect_state_cell(
  state : Ref[SheetState],
  cell : String,
) -> @typed_spreadsheet.CellSnapshot {
  state.val.adapter.inspect_cell(cell)
}

///|
test "sheet planner covers messages and owns submitted payloads" {
  let context = test_sheet_planning_context()
  let selected = context.selected_cell
  match plan_sheet_command(context, ApplySelected).command {
    Some(ApplyFromSelection(target, text, generation)) => {
      assert_true(target == selected)
      assert_true(text == "=A1 + 1")
      assert_true(generation == context.generation)
    }
    _ => abort("expected selected apply")
  }
  match plan_sheet_command(context, ApplyInlineEdit("C1")) {
    {
      command: Some(ApplyFromEditor(target, text, generation)),
      ui_effect: None,
    } => {
      assert_true(@demo.cell_id_to_string(target) == "C1")
      assert_true(text == "7")
      assert_true(generation == context.generation)
    }
    _ => abort("expected inline apply")
  }
  match plan_sheet_command(context, DeleteSelected).command {
    Some(DeleteFromSelection(target, generation)) => {
      assert_true(target == selected)
      assert_true(generation == context.generation)
    }
    _ => abort("expected delete")
  }
  match plan_sheet_command(context, ResetSheet).command {
    Some(ResetDocument(generation)) =>
      assert_true(generation == context.generation)
    _ => abort("expected reset")
  }
  match plan_sheet_command(context, BeginInlineEdit("C1")) {
    { command: None, ui_effect: Some(FocusInlineEditor(address)) } =>
      assert_true(address == "C1")
    _ => abort("expected inline focus")
  }
  match plan_sheet_command(context, BeginSelectedInlineEdit) {
    { command: None, ui_effect: Some(FocusInlineEditor(address)) } =>
      assert_true(address == "B1")
    _ => abort("expected selected focus")
  }
  for
    msg in [
      SelectCell("A1"),
      UpdateDraft("A1", "x"),
      UseExample("x"),
      CancelSelected,
      MoveSelection(1, 0),
    ] {
    let plan = plan_sheet_command(context, msg)
    assert_true(plan.command is None)
    assert_true(plan.ui_effect is None)
  }
}

///|
test "owned planning context does not follow later draft mutation" {
  let source : Array[CellDraft] = [
    { cell: "A1", text: "10" },
    { cell: "B1", text: "=A1 + 1" },
  ]
  let context = {
    ..test_sheet_planning_context(),
    drafts: ReadOnlyArray::from_array(source),
  }
  source[1] = { cell: "B1", text: "changed" }
  match plan_sheet_command(context, ApplySelected).command {
    Some(ApplyFromSelection(_, text, _)) => assert_true(text == "=A1 + 1")
    _ => abort("expected apply")
  }
}

///|
test "apply operation preserves the submitted typed target" {
  let runtime = @incr.Runtime()
  let app = try! TypedSheetApp(runtime)
  let foreign_target = @typed_spreadsheet.CellId::of(
    @typed_spreadsheet.SheetId(99),
    "A1",
  )
  ignore(
    execute_sheet_command(
      runtime,
      app._state,
      ApplyFromSelection(
        foreign_target,
        "42",
        app._state.val.adapter.generation(),
      ),
    ),
  )
  inspect(
    cell_result_text(inspect_state_cell(app._state, "A1").result),
    content="10",
  )
  app.dispose()
}

///|
test "direct execution uses submitted text and rejects stale generation" {
  let runtime = @incr.Runtime()
  let app = try! TypedSheetApp(runtime)
  app._state.val.selected_cell.set("A1")
  app._state.val.drafts.set(
    update_draft(app._state.val.drafts.peek(), "A1", "42"),
  )
  let plan = plan_sheet_command(
    sheet_planning_context(app._state),
    ApplySelected,
  )
  app._state.val.drafts.set(
    update_draft(app._state.val.drafts.peek(), "A1", "99"),
  )
  let command = match plan.command {
    Some(command) => command
    None => abort("expected command")
  }
  assert_true(execute_sheet_command(runtime, app._state, command) == Applicable)
  inspect(
    cell_result_text(inspect_state_cell(app._state, "A1").result),
    content="42",
  )
  let generation = app._state.val.adapter.generation()
  let reset = match
    plan_sheet_command(sheet_planning_context(app._state), ResetSheet).command {
    Some(command) => command
    None => abort("expected reset")
  }
  assert_true(execute_sheet_command(runtime, app._state, reset) == Applicable)
  assert_true(app._state.val.adapter.generation() == generation.next())
  inspect(
    app._state.val.status.peek(),
    content="Ready. This incr_tea proof is separate from the live Rabbita demo.",
  )
  inspect(app._state.val.last_edit.peek(), content="Seed sheet")
  assert_true(app._state.val.trace.peek() is None)
  assert_true(app._state.val.evidence.peek() is None)
  assert_true(
    execute_sheet_command(runtime, app._state, command) == StaleGeneration,
  )
  inspect(
    cell_result_text(inspect_state_cell(app._state, "A1").result),
    content="10",
  )
  inspect(
    cell_result_text(inspect_state_cell(app._state, "B1").result),
    content="11",
  )
  app.dispose()
}

///|
test "direct execution rejects failed selected editing and delete preconditions" {
  let runtime = @incr.Runtime()
  let app = try! TypedSheetApp(runtime)

  app._state.val.selected_cell.set("A1")
  app._state.val.drafts.set(
    update_draft(app._state.val.drafts.peek(), "A1", "42"),
  )
  let selected_apply = match
    plan_sheet_command(sheet_planning_context(app._state), ApplySelected).command {
    Some(command) => command
    None => abort("expected selected apply")
  }
  app._state.val.selected_cell.set("B1")
  assert_true(
    execute_sheet_command(runtime, app._state, selected_apply) ==
    LocalPreconditionFailed,
  )
  inspect(
    cell_result_text(inspect_state_cell(app._state, "A1").result),
    content="10",
  )

  let c1_before = cell_result_text(inspect_state_cell(app._state, "C1").result)
  app._state.val.editing_cell.set(Some("C1"))
  app._state.val.drafts.set(
    update_draft(app._state.val.drafts.peek(), "C1", "7"),
  )
  let inline_apply = match
    plan_sheet_command(
      sheet_planning_context(app._state),
      ApplyInlineEdit("C1"),
    ).command {
    Some(command) => command
    None => abort("expected inline apply")
  }
  app._state.val.editing_cell.set(Some("D1"))
  assert_true(
    execute_sheet_command(runtime, app._state, inline_apply) ==
    LocalPreconditionFailed,
  )
  assert_true(
    cell_result_text(inspect_state_cell(app._state, "C1").result) == c1_before,
  )

  app._state.val.selected_cell.set("A1")
  let delete = match
    plan_sheet_command(sheet_planning_context(app._state), DeleteSelected).command {
    Some(command) => command
    None => abort("expected delete")
  }
  app._state.val.selected_cell.set("B1")
  assert_true(
    execute_sheet_command(runtime, app._state, delete) ==
    LocalPreconditionFailed,
  )
  inspect(
    cell_result_text(inspect_state_cell(app._state, "A1").result),
    content="10",
  )
  inspect(app._state.val.last_edit.peek(), content="Seed sheet")
  app.dispose()
}

///|
test "browser command advances EGW authority before projection" {
  let app = try! TypedSheetApp(@incr.Runtime())
  let before = app._state.val.adapter.version()
  ignore(app.prog_grid.dispatch(SelectCell("A1")))
  ignore(app.prog_grid.dispatch(UpdateDraft("A1", "15")))
  ignore(app.prog_grid.dispatch(ApplySelected))
  let state = app._state.val
  assert_true(state.adapter.version() != before)
  inspect(
    cell_result_text(state.adapter.inspect_cell("A1").result),
    content="15",
  )
  inspect(
    cell_result_text(state.adapter.inspect_cell("B1").result),
    content="16",
  )
  app.dispose()
}

///|
test "adapter-backed execution applies a valid delete" {
  let app = try! TypedSheetApp(@incr.Runtime())
  ignore(app.prog_grid.dispatch(SelectCell("A1")))
  ignore(app.prog_grid.dispatch(DeleteSelected))
  let state = app._state.val
  inspect(state.adapter.inspect_cell("A1").present, content="false")
  inspect(draft_text_from(state.committed.peek(), "A1"), content="")
  inspect(draft_text_from(state.drafts.peek(), "A1"), content="")
  inspect(state.last_edit.peek(), content="delete A1")
  assert_true(state.trace.peek() is Some(_))
  assert_true(state.evidence.peek() is Some(_))
  app.dispose()
}

///|
test "adapter-backed reset replaces dirty drafts with seed state" {
  let app = try! TypedSheetApp(@incr.Runtime())
  let before = app._state.val.adapter.generation()
  ignore(app.prog_grid.dispatch(SelectCell("C1")))
  ignore(app.prog_grid.dispatch(UpdateDraft("C1", "99")))
  ignore(app.prog_grid.dispatch(ResetSheet))
  let state = app._state.val
  assert_true(state.adapter.generation() == before.next())
  inspect(draft_text_from(state.drafts.peek(), "A1"), content="10")
  inspect(draft_text_from(state.drafts.peek(), "B1"), content="=A1 + 1")
  inspect(draft_text_from(state.drafts.peek(), "C1"), content="")
  inspect(draft_text_from(state.committed.peek(), "A1"), content="10")
  inspect(draft_text_from(state.committed.peek(), "B1"), content="=A1 + 1")
  inspect(draft_text_from(state.committed.peek(), "C1"), content="")
  inspect(
    cell_result_text(state.adapter.inspect_cell("A1").result),
    content="10",
  )
  inspect(
    cell_result_text(state.adapter.inspect_cell("B1").result),
    content="11",
  )
  app.dispose()
}
