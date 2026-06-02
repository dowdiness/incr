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
  inspect(model.intro_visible, content="true")
  inspect(
    friendly_snapshot_result(model.sheet.inspect_cell(cell_id(model, "A1"))),
    content="Int(10)",
  )
  inspect(
    friendly_snapshot_result(model.sheet.inspect_cell(cell_id(model, "B1"))),
    content="Int(11)",
  )
  inspect(model.grid_snapshot_cache.length(), content="2")
  inspect(
    friendly_grid_result(grid_snapshot_for(model, "A1")),
    content="Int(10)",
  )
  inspect(
    friendly_grid_result(grid_snapshot_for(model, "B1")),
    content="Int(11)",
  )
  inspect(
    friendly_grid_result(grid_snapshot_for(model, "AX50")),
    content="Empty cell",
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
  inspect(applied.grid_snapshot_cache.length(), content="2")
  inspect(
    friendly_grid_result(grid_snapshot_for(applied, "A1")),
    content="Int(15)",
  )
  inspect(
    friendly_grid_result(grid_snapshot_for(applied, "B1")),
    content="Int(16)",
  )
  match applied.last_step {
    // Bounded evidence: a plain input edit captures only the edited cell, not
    // every grid cell. See issue #129 Phase 1.
    Some(step) => inspect(step.cell_snapshots.length(), content="1")
    None => abort("expected applied edit")
  }
  let (recomputed, changed, unchanged) = trace_cells(applied)
  debug_inspect(recomputed, content="[\"B1\"]")
  debug_inspect(changed, content="[\"B1\"]")
  debug_inspect(unchanged, content="[]")
}

///|
test "typed spreadsheet Rabbita grid render keeps the sparse snapshot cache unchanged" {
  let model = init_model()

  ignore(view(noop_emit, model))

  inspect(model.grid_snapshot_cache.length(), content="2")
  inspect(
    friendly_grid_result(grid_snapshot_for(model, "AX50")),
    content="Empty cell",
  )
}

///|
test "typed spreadsheet Rabbita grid snapshot cache refreshes deletes and changed dependents" {
  let model = init_model()
  let selected = update(SelectCell("A1"), model)
  let deleted = update(DeleteSelected, selected)

  inspect(deleted.grid_snapshot_cache.length(), content="1")
  inspect(
    friendly_grid_result(grid_snapshot_for(deleted, "A1")),
    content="Empty cell",
  )
  inspect(
    grid_status_label(grid_snapshot_for(deleted, "B1")),
    content="ref error",
  )
  inspect(
    grid_cell_display_value(grid_snapshot_for(deleted, "B1")),
    content="ref error",
  )
}

///|
test "typed spreadsheet Rabbita editor bounds snapshot evidence to the edited cell (issue #129)" {
  let model = init_model()
  let drafted = update(UpdateDraft("A1", "15"), model)
  let applied = update(ApplySelected, drafted)

  match applied.last_step {
    Some(step) => {
      // A single ordinary edit must NOT retain a snapshot per grid cell.
      inspect(step.cell_snapshots.length(), content="1")
      inspect(
        step.cell_snapshots.length() < model.cells.length(),
        content="true",
      )
      // The captured snapshot is the edited cell itself.
      inspect(@demo.cell_id_to_string(step.cell_snapshots[0].id), content="A1")
    }
    None => abort("expected applied edit")
  }
}

///|
test "typed spreadsheet Rabbita editor captures a formula's direct references, still bounded (issue #129)" {
  let model = init_model()
  let drafted = update(UpdateDraft("C1", "=A1 + 1"), model)
  let applied = update(ApplySelected, drafted)

  match applied.last_step {
    Some(step) =>
      // Target C1 plus its one direct reference A1 — bounded to the formula's
      // affected surface, far below the 2,500 grid cells.
      inspect(step.cell_snapshots.length(), content="2")
    None => abort("expected applied edit")
  }
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
test "typed spreadsheet Rabbita editor handles an empty edit gracefully" {
  let model = init_model()
  let drafted = update(UpdateDraft("A1", ""), model)
  let applied = update(ApplySelected, drafted)

  // Empty input fails gracefully: no error styling, no forced editor pop,
  // calm status, and the cell keeps its committed value.
  inspect(applied.error is None, content="true")
  inspect(applied.status, content="Left A1 unchanged.")
  inspect(overlay_status(applied.overlay), content="Panels hidden.")
  inspect(draft_for(applied, "A1"), content="10")
  inspect(
    friendly_snapshot_result(applied.sheet.inspect_cell(cell_id(applied, "A1"))),
    content="Int(10)",
  )
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
  let left = update(MoveSelection(-1, 0), model)
  let down = update(MoveSelection(0, 1), left)
  let right = update(MoveSelection(1, 0), down)
  let up = update(MoveSelection(0, -1), right)

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
test "typed spreadsheet Rabbita editor closes intro independently" {
  let model = init_model()
  let closed_intro = update(CloseIntro, model)
  let closed_again = update(CloseIntro, closed_intro)
  let reset = update(ResetSheet, closed_intro)

  inspect(closed_intro.intro_visible, content="false")
  inspect(closed_again.intro_visible, content="false")
  inspect(reset.intro_visible, content="true")
}

///|
test "typed spreadsheet Rabbita editor supports direct cell editing mode" {
  let model = init_model()
  let editing = update(BeginInlineEdit("C1"), model)
  let drafted = update(UpdateDraft("C1", "7"), editing)
  let moved = update(MoveSelection(1, 0), drafted)
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
fn noop_emit(_msg : Msg) -> @rabbita.Cmd {
  @rabbita.none
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
