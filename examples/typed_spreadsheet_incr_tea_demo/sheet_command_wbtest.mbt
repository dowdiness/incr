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
test "sheet planner covers messages and owns submitted payloads" {
  let context = test_sheet_planning_context()
  let selected = context.selected_cell
  match plan_sheet_command(context, UseExample("15")).command {
    Some(ApplyFromSelection(target, text, generation)) => {
      assert_true(target == selected)
      assert_true(text == "15")
      assert_true(generation == context.generation)
    }
    _ => abort("expected example apply")
  }
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
test "interpreter executes the submitted text captured by planning" {
  let runtime = @incr.Runtime()
  let state = Ref(try! SheetState::new(runtime, SheetStartMode::Standalone))
  state.val.selected_cell.set("A1")
  state.val.drafts.set(update_draft(state.val.drafts.peek(), "A1", "42"))
  let command = match
    plan_sheet_command(sheet_planning_context(state), ApplySelected).command {
    Some(command) => command
    None => abort("expected planned apply")
  }
  state.val.drafts.set(update_draft(state.val.drafts.peek(), "A1", "99"))

  assert_true(execute_sheet_command(runtime, state, command) == Applicable)
  let context = state.val.ai_context_snapshot(region=["A1"])
  inspect(context.cells[0].committed_text, content="42")
  inspect(context.cells[0].draft_text, content="99")
  inspect(context.cells[0].result.repr, content="Ok(Int(42))")
  state.val.adapter.dispose()
  state.val._scope.dispose()
}
