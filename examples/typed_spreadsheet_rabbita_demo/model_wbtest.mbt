///|
test "typed spreadsheet Rabbita editor starts with seeded sheet and no user trace" {
  let model = init_model()

  inspect(model.selected_cell, content="B1")
  inspect(model.last_edit, content="Seed sheet")
  inspect(model.last_step is None, content="true")
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
  inspect(
    friendly_snapshot_result(applied.sheet.inspect_cell(cell_id(applied, "A1"))),
    content="Int(15)",
  )
  inspect(
    friendly_snapshot_result(applied.sheet.inspect_cell(cell_id(applied, "B1"))),
    content="Int(16)",
  )
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
