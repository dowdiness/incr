///|
test "typed spreadsheet Rabbita editor starts with seeded sheet and no user trace" {
  let model = init_model()

  inspect(model.selected_cell, content="B1")
  inspect(model.cells.length(), content="2500")
  inspect(model.cells[0], content="A1")
  inspect(model.cells[2499], content="AX50")
  inspect(model.last_edit, content="Seed sheet")
  inspect(model.last_step is None, content="true")
  inspect(appearance_label(model.appearance), content="paper")
  inspect(overlay_status(model.overlay), content="Panels hidden.")
  inspect(
    friendly_snapshot_result(model.sheet.inspect_cell(cell_id(model, "A1"))),
    content="Int(10)",
  )
  inspect(
    friendly_snapshot_result(model.sheet.inspect_cell(cell_id(model, "B1"))),
    content="Int(11)",
  )
}

///|
test "typed spreadsheet Rabbita editor applies selected draft and captures formula trace" {
  let model = init_model()
  let drafted = update(UpdateDraft("A1", "15"), model)
  let applied = update(ApplySelected, drafted)

  inspect(applied.selected_cell, content="A1")
  inspect(applied.last_edit, content="A1 ← 15")
  inspect(applied.error is None, content="true")
  inspect(overlay_status(applied.overlay), content="Panels hidden.")
  inspect(committed_for(applied, "A1"), content="15")
  inspect(
    friendly_snapshot_result(applied.sheet.inspect_cell(cell_id(applied, "A1"))),
    content="Int(15)",
  )
  inspect(
    friendly_snapshot_result(applied.sheet.inspect_cell(cell_id(applied, "B1"))),
    content="Int(16)",
  )
  match applied.last_step {
    Some(step) => inspect(step.cell_snapshots.length(), content="2500")
    None => abort("expected applied edit")
  }
  let (recomputed, changed, unchanged) = trace_cells(applied)
  debug_inspect(recomputed, content="[\"B1\"]")
  debug_inspect(changed, content="[\"B1\"]")
  debug_inspect(unchanged, content="[]")
}

///|
test "typed spreadsheet Rabbita editor leaves worksheet unchanged after parse error" {
  let model = init_model()
  let drafted = update(UpdateDraft("A1", "oops"), model)
  let failed = update(ApplySelected, drafted)

  inspect(failed.status, content="Edit not applied.")
  match failed.error {
    Some(message) =>
      inspect(message, content="Could not read oops as an integer.")
    None => abort("expected parse error")
  }
  inspect(
    friendly_snapshot_result(failed.sheet.inspect_cell(cell_id(failed, "A1"))),
    content="Int(10)",
  )
  inspect(failed.last_step is None, content="true")
}

///|
test "typed spreadsheet Rabbita editor reset disposes old worksheet" {
  let model = init_model()
  let old_sheet = model.sheet
  let reset = update(ResetSheet, model)

  inspect(old_sheet.is_disposed(), content="true")
  inspect(reset.sheet.is_disposed(), content="false")
  inspect(reset.selected_cell, content="B1")
}

///|
test "typed spreadsheet Rabbita editor moves selection with grid arrow keys" {
  let model = init_model()
  let left = update(HandleGridKey(test_key("ArrowLeft")), model)
  let down = update(HandleGridKey(test_key("ArrowDown")), left)
  let right = update(HandleGridKey(test_key("ArrowRight")), down)
  let up = update(HandleGridKey(test_key("ArrowUp")), right)

  inspect(left.selected_cell, content="A1")
  inspect(down.selected_cell, content="A2")
  inspect(right.selected_cell, content="B2")
  inspect(up.selected_cell, content="B1")
}

///|
test "typed spreadsheet Rabbita editor escape reverts draft text" {
  let model = init_model()
  let drafted = update(UpdateDraft("A1", "15"), model)
  let cancelled = update(HandleAppKey(test_key("Escape")), drafted)

  inspect(cancelled.selected_cell, content="A1")
  inspect(draft_for(cancelled, "A1"), content="10")
  inspect(
    friendly_snapshot_result(
      cancelled.sheet.inspect_cell(cell_id(cancelled, "A1")),
    ),
    content="Int(10)",
  )
}

///|
test "typed spreadsheet Rabbita editor appearance and inspector toggles are values" {
  let model = init_model()
  let night = update(SetAppearance(Night), model)
  let trace = update(SetOverlay(TraceOverlay), night)
  let closed = update(SetOverlay(TraceOverlay), trace)

  inspect(appearance_label(night.appearance), content="night")
  inspect(overlay_status(trace.overlay), content="Trace inspector open.")
  inspect(overlay_status(closed.overlay), content="Panels hidden.")
}

///|
test "typed spreadsheet Rabbita editor supports direct cell editing mode" {
  let model = init_model()
  let editing = update(BeginInlineEdit("C1"), model)
  let drafted = update(UpdateDraft("C1", "7"), editing)
  let moved = update(HandleGridKey(test_key("ArrowRight")), drafted)
  let applied = update(ApplyInlineEdit("C1"), moved)
  let stale_blur = update(ApplyInlineEdit("C1"), applied)

  inspect(editing.selected_cell, content="C1")
  match editing.editing_cell {
    Some(cell) => inspect(cell, content="C1")
    None => abort("expected inline editor")
  }
  inspect(moved.selected_cell, content="C1")
  inspect(
    friendly_snapshot_result(applied.sheet.inspect_cell(cell_id(applied, "C1"))),
    content="Int(7)",
  )
  inspect(applied.editing_cell is None, content="true")
  inspect(stale_blur.last_edit, content="C1 ← 7")
}

///|
fn test_key(key : String) -> @html.Keyboard {
  @html.Keyboard::new(
    key~,
    code=key,
    alt_key=false,
    ctrl_key=false,
    shift_key=false,
    meta_key=false,
    is_composing=false,
    repeat=false,
    location=0,
  )
}
