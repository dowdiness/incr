///|
fn new_model_application() -> TypedSheetApplication {
  match
    TypedSheetApplication::start(
      @incr.Runtime(),
      SheetStartMode::Standalone,
      None,
      AiContextPublisher::AiContextPublisher(_ => ()),
    ) {
    Ok(app) => app
    Err(_) => abort("standalone application failed to start")
  }
}

///|
fn observed_cell(
  snapshot : @demo.AiContextSnapshot,
  cell : String,
) -> @demo.AiContextCell {
  match snapshot.cells.search_by(row => row.id == cell) {
    Some(index) => snapshot.cells[index]
    None => abort("missing observed cell: \{cell}")
  }
}

///|
fn observed_draft(snapshot : ApplicationSnapshot, cell : String) -> String {
  match snapshot.drafts.search_by(draft => draft.cell == cell) {
    Some(index) => snapshot.drafts[index].text
    None => ""
  }
}

///|
test "incr_tea spreadsheet proof starts with seeded representative grid" {
  let app = new_model_application()
  let observation = app.observe()
  let snapshot = observation.snapshot
  let context = snapshot.ai_context

  inspect(context.selected_cell, content="B1")
  inspect(grid_cells().length(), content="2500")
  inspect(context.latest_trace is None, content="true")
  inspect(observed_draft(snapshot, "A1"), content="10")
  inspect(observed_draft(snapshot, "B1"), content="=A1 + 1")
  ignore(app.dispatch(SelectCell("A1")))
  inspect(
    app.observe().snapshot.ai_context.cells[0].result.repr,
    content="Ok(Int(10))",
  )
  ignore(app.dispatch(SelectCell("B1")))
  inspect(
    app.observe().snapshot.ai_context.cells[0].result.repr,
    content="Ok(Int(11))",
  )
  ignore(app.dispatch(SelectCell("C1")))
  let missing = observed_cell(app.observe().snapshot.ai_context, "C1")
  inspect(missing.present, content="false")
  inspect(missing.result.status, content="missing")

  app.dispose()
}

///|
test "present direct formula reference preserves missing Blank" {
  let app = new_model_application()
  ignore(app.dispatch(BeginInlineEdit("C1")))
  ignore(app.dispatch(UpdateDraft("C1", "=Z1")))
  ignore(app.dispatch(ApplyInlineEdit("C1")))
  let context = app.observe().snapshot.ai_context
  let cell = observed_cell(context, "C1")
  inspect(cell.present, content="true")
  inspect(cell.result.status, content="ok")
  inspect(cell.result.repr, content="Ok(Blank)")
  app.dispose()
}

///|
test "incr_tea spreadsheet proof exposes pure editor state through observation" {
  let app = new_model_application()
  ignore(app.dispatch(BeginInlineEdit("C1")))
  ignore(app.dispatch(UpdateDraft("C1", "7")))
  let snapshot = app.observe().snapshot

  debug_inspect(snapshot.editing_cell, content="Some(\"C1\")")
  debug_inspect(snapshot.error, content="None")
  inspect(snapshot.last_edit, content="Seed sheet")
  inspect(observed_draft(snapshot, "C1"), content="7")
  app.dispose()
}

///|
test "collaboration rejects reset before shared mutation" {
  let recording = RecordingSessionTransport::RecordingSessionTransport()
  let app = match
    TypedSheetApplication::start(
      @incr.Runtime(),
      SheetStartMode::Host("room", ReplicaId("reset-model-test")),
      Some(recording.port()),
      AiContextPublisher::AiContextPublisher(_ => ()),
    ) {
    Ok(app) => app
    Err(_) => abort("collaborative application failed to start")
  }
  let outcome = match app.dispatch(ResetSheet) {
    Ok(outcome) => outcome
    Err(_) => abort("collaboration reset dispatch was rejected")
  }
  inspect(outcome.authority_changed, content="false")
  let snapshot = app.observe().snapshot
  inspect(snapshot.status, content="Reset is unavailable while collaborating.")
  debug_inspect(
    snapshot.error,
    content="Some(\"Collaboration keeps one shared document generation.\")",
  )
  inspect(recording.published.val.length(), content="0")
  app.dispose()
}

///|
test "collaboration publish retains edit detail and local fallback stays local" {
  let recording = RecordingSessionTransport::RecordingSessionTransport()
  let app = match
    TypedSheetApplication::start(
      @incr.Runtime(),
      SheetStartMode::Host("room", ReplicaId("model-test")),
      Some(recording.port()),
      AiContextPublisher::AiContextPublisher(_ => ()),
    ) {
    Ok(app) => app
    Err(_) => abort("collaborative application failed to start")
  }
  ignore(app.dispatch(BeginInlineEdit("C1")))
  ignore(app.dispatch(UpdateDraft("C1", "7")))
  ignore(app.dispatch(ApplyInlineEdit("C1")))
  let shared_status = app.observe().snapshot.status
  inspect(recording.published.val.length(), content="1")
  inspect(shared_status.contains("Applied C1 ← 7:"), content="true")
  inspect(shared_status.contains("Shared update sent."), content="true")

  inspect(recording.fail("transport failed"), content="true")
  ignore(app.dispatch(BeginInlineEdit("C1")))
  ignore(app.dispatch(UpdateDraft("C1", "8")))
  ignore(app.dispatch(ApplyInlineEdit("C1")))
  let local_status = app.observe().snapshot.status
  inspect(recording.published.val.length(), content="1")
  inspect(local_status.contains("Applied C1 ← 8:"), content="true")
  inspect(local_status.contains("Shared update sent."), content="false")
  app.dispose()
}

///|
test "incr_tea spreadsheet proof applies and cancels through application dispatch" {
  let app = new_model_application()

  ignore(app.dispatch(BeginInlineEdit("C1")))
  ignore(app.dispatch(UpdateDraft("C1", "7")))
  ignore(app.dispatch(MoveSelection(1, 0)))
  ignore(app.dispatch(ApplyInlineEdit("C1")))
  let applied = app.observe().snapshot

  inspect(applied.ai_context.selected_cell, content="C1")
  inspect(applied.editing_cell is None, content="true")
  inspect(
    observed_cell(applied.ai_context, "C1").result.repr,
    content="Ok(Int(7))",
  )
  inspect(applied.last_edit, content="C1 ← 7")

  ignore(app.dispatch(BeginInlineEdit("C1")))
  ignore(app.dispatch(UpdateDraft("C1", "8")))
  ignore(app.dispatch(CancelSelected))
  let cancelled = app.observe().snapshot
  inspect(observed_draft(cancelled, "C1"), content="7")
  inspect(
    observed_cell(cancelled.ai_context, "C1").result.repr,
    content="Ok(Int(7))",
  )
  app.dispose()
}

///|
test "incr_tea spreadsheet proof applies formula bar edits and dependent formulas update" {
  let app = new_model_application()
  ignore(app.dispatch(SelectCell("A1")))
  ignore(app.dispatch(UpdateDraft("A1", "15")))
  ignore(app.dispatch(ApplySelected))
  let observation = app.observe().snapshot
  let context = observation.ai_context

  inspect(observation.last_edit, content="A1 ← 15")
  inspect(observed_cell(context, "A1").result.repr, content="Ok(Int(15))")
  inspect(observed_cell(context, "B1").result.repr, content="Ok(Int(16))")
  match context.latest_trace {
    Some(trace) => inspect(trace.changed.contains("B1"), content="true")
    None => abort("expected applied edit")
  }
  app.dispose()
}

///|
test "incr_tea spreadsheet proof maps payload descriptors at renderer boundary" {
  match resolve_value(@tea.ValueEventId("draft:A1"), @tea.ValuePayload("15")) {
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

///|
test "incr_tea locality: draft-only does not change status" {
  let app = new_model_application()
  let initial_status = app.observe().snapshot.status

  ignore(app.dispatch(UpdateDraft("C1", "99")))
  let after_draft = app.observe().snapshot
  inspect(after_draft.status, content=initial_status)

  ignore(app.dispatch(SelectCell("A1")))
  let after_select = app.observe().snapshot
  inspect(after_select.status, content="Selected A1.")
  app.dispose()
}

///|
test "example click applies the selected cell immediately" {
  let app = new_model_application()
  ignore(app.dispatch(SelectCell("A1")))
  ignore(app.dispatch(UseExample("15")))
  let snapshot = app.observe().snapshot
  inspect(observed_draft(snapshot, "A1"), content="15")
  inspect(
    observed_cell(snapshot.ai_context, "A1").result.repr,
    content="Ok(Int(15))",
  )
  inspect(
    observed_cell(snapshot.ai_context, "B1").result.repr,
    content="Ok(Int(16))",
  )
  app.dispose()
}

///|
test "delete clears local projections and records semantic evidence" {
  let app = new_model_application()
  ignore(app.dispatch(SelectCell("A1")))
  let outcome = match app.dispatch(DeleteSelected) {
    Ok(outcome) => outcome
    Err(_) => abort("delete dispatch was rejected")
  }
  let snapshot = app.observe().snapshot
  inspect(outcome.authority_changed, content="true")
  inspect(observed_draft(snapshot, "A1"), content="")
  let deleted = observed_cell(snapshot.ai_context, "A1")
  inspect(deleted.present, content="false")
  inspect(deleted.committed_text, content="")
  inspect(snapshot.last_edit, content="delete A1")
  inspect(snapshot.ai_context.latest_trace is Some(_), content="true")
  inspect(snapshot.ai_context.latest_evidence is Some(_), content="true")
  app.dispose()
}

///|
test "incr_tea spreadsheet proof covers the practical 50x50 grid" {
  inspect(grid_column_count(), content="50")
  inspect(grid_row_count(), content="50")
  let labels = column_labels()
  inspect(labels.length(), content="50")
  inspect(labels[0], content="A")
  inspect(labels[49], content="AX")
  let cells = grid_cells()
  inspect(cells.length(), content="2500")
  inspect(cells[0], content="A1")
  inspect(cells[2499], content="AX50")
}

///|
test "incr_tea spreadsheet proof clamps selection at 50x50 boundaries" {
  let app = new_model_application()
  ignore(app.dispatch(SelectCell("AX50")))
  ignore(app.dispatch(MoveSelection(1, 0)))
  inspect(app.observe().snapshot.ai_context.selected_cell, content="AX50")
  ignore(app.dispatch(MoveSelection(0, 1)))
  inspect(app.observe().snapshot.ai_context.selected_cell, content="AX50")
  ignore(app.dispatch(SelectCell("A1")))
  ignore(app.dispatch(MoveSelection(-1, 0)))
  inspect(app.observe().snapshot.ai_context.selected_cell, content="A1")
  ignore(app.dispatch(MoveSelection(0, -1)))
  inspect(app.observe().snapshot.ai_context.selected_cell, content="A1")
  app.dispose()
}

///|
struct ModelContextFixture {
  runtime : @incr.Runtime
  state : Ref[SheetState]
}

///|
fn new_model_context_fixture() -> ModelContextFixture {
  let runtime = @incr.Runtime()
  {
    runtime,
    state: Ref(try! SheetState::new(runtime, SheetStartMode::Standalone)),
  }
}

///|
fn ModelContextFixture::dispatch(self : ModelContextFixture, msg : Msg) -> Unit {
  // This fixture is intentionally source-owned. ApplicationObservation exposes
  // the default AI context only; custom region/max_cells contracts must exercise
  // SheetState::ai_context_snapshot without reaching through the application.
  let (plan, immediate) = prepare_sheet_dispatch(self.state, msg)
  ignore(immediate)
  execute_sheet_plan(self.runtime, self.state, plan)
}

///|
fn ModelContextFixture::snapshot(
  self : ModelContextFixture,
  region? : Array[String],
  max_cells? : Int = 64,
) -> @demo.AiContextSnapshot {
  self.state.val.ai_context_snapshot(region?, max_cells~)
}

///|
fn ModelContextFixture::dispose(self : ModelContextFixture) -> Unit {
  self.state.val.adapter.dispose()
  self.state.val._scope.dispose()
}

///|
test "incr_tea AI context stays schema-versioned and bounded" {
  let fixture = new_model_context_fixture()
  let context = fixture.snapshot(region?=Some(["A1", "B1", "C1"]), max_cells=2)
  inspect(context.schema_version, content="3")
  inspect(context.selected_cell, content="B1")
  inspect(context.max_cells, content="2")
  inspect(context.truncated, content="true")
  inspect(context.region.length(), content="2")
  inspect(context.region[0], content="B1")
  inspect(context.cells.length(), content="2")
  inspect(context.cells[0].committed_text, content="=A1 + 1")
  inspect(context.cells[0].draft_text, content="=A1 + 1")
  inspect(context.cells[0].draft_dirty, content="false")
  inspect(context.latest_trace is None, content="true")
  inspect(context.latest_evidence is None, content="true")
  fixture.dispose()
}

///|
test "incr_tea AI context carries latest trace and evidence" {
  let app = new_model_application()
  ignore(app.dispatch(SelectCell("A1")))
  ignore(app.dispatch(UpdateDraft("A1", "15")))
  ignore(app.dispatch(ApplySelected))
  let context = app.observe().snapshot.ai_context
  match context.latest_trace {
    Some(trace) => {
      inspect(trace.edit, content="A1 ← 15")
      inspect(trace.changed.contains("B1"), content="true")
    }
    None => abort("expected latest trace")
  }
  match context.latest_evidence {
    Some(evidence) => {
      inspect(evidence.edit, content="A1 ← 15")
      inspect(evidence.cells.length(), content="2")
      let edited = evidence.cells[0]
      inspect(edited.id, content="A1")
      inspect(edited.classification, content="changed")
      inspect(edited.before_kind, content="input")
      inspect(edited.before.status, content="ok")
      inspect(edited.before.repr, content="Ok(Int(10))")
      inspect(edited.after_kind, content="input")
      inspect(edited.after.status, content="ok")
      inspect(edited.after.repr, content="Ok(Int(15))")
      let dependent = evidence.cells[1]
      inspect(dependent.id, content="B1")
      inspect(dependent.classification, content="changed")
      inspect(dependent.before_kind, content="formula")
      inspect(dependent.before.status, content="ok")
      inspect(dependent.before.repr, content="Ok(Int(11))")
      inspect(dependent.after_kind, content="formula")
      inspect(dependent.after.status, content="ok")
      inspect(dependent.after.repr, content="Ok(Int(16))")
    }
    None => abort("expected latest evidence")
  }
  let outcome = match app.dispatch(ResetSheet) {
    Ok(outcome) => outcome
    Err(_) => abort("reset dispatch was rejected")
  }
  let reset = app.observe().snapshot
  inspect(outcome.authority_changed, content="true")
  inspect(reset.ai_context.selected_cell, content="B1")
  inspect(observed_draft(reset, "A1"), content="10")
  inspect(observed_draft(reset, "B1"), content="=A1 + 1")
  inspect(observed_draft(reset, "C1"), content="")
  inspect(
    observed_cell(reset.ai_context, "A1").result.repr,
    content="Ok(Int(10))",
  )
  inspect(
    observed_cell(reset.ai_context, "B1").result.repr,
    content="Ok(Int(11))",
  )
  inspect(
    reset.status,
    content="Ready. This incr_tea proof is separate from the live Rabbita demo.",
  )
  inspect(reset.last_edit, content="Seed sheet")
  inspect(reset.ai_context.latest_trace is None, content="true")
  inspect(reset.ai_context.latest_evidence is None, content="true")
  app.dispose()
}

///|
test "incr_tea evidence capture stays bounded for many direct dependents" {
  let app = new_model_application()
  for row in 2..<=20 {
    let cell = "B\{row}"
    ignore(app.dispatch(SelectCell(cell)))
    ignore(app.dispatch(UpdateDraft(cell, "=A1")))
    ignore(app.dispatch(ApplySelected))
  }
  // Make A1 the captured edit target so the public observation exposes the
  // same direct-dependent evidence path without reaching through SheetState.
  ignore(app.dispatch(SelectCell("A1")))
  ignore(app.dispatch(UpdateDraft("A1", "11")))
  ignore(app.dispatch(ApplySelected))
  let context = app.observe().snapshot.ai_context
  match context.latest_evidence {
    Some(evidence) => {
      inspect(evidence.cells.length(), content="16")
      inspect(evidence.cells[0].id, content="A1")
      inspect(evidence.cells[1].id, content="B1")
      inspect(evidence.cells[2].id, content="B2")
      inspect(evidence.cells[15].id, content="B15")
    }
    None => abort("expected bounded evidence")
  }
  app.dispose()
}

///|
test "incr_tea evidence distinguishes unchanged formula recomputation" {
  let app = new_model_application()
  ignore(app.dispatch(SelectCell("B1")))
  ignore(app.dispatch(UpdateDraft("B1", "=A1 * 0")))
  ignore(app.dispatch(ApplySelected))
  ignore(app.dispatch(SelectCell("A1")))
  ignore(app.dispatch(UpdateDraft("A1", "15")))
  ignore(app.dispatch(ApplySelected))
  let context = app.observe().snapshot.ai_context
  match context.latest_evidence {
    Some(evidence) => {
      inspect(evidence.cells.length(), content="2")
      inspect(evidence.cells[1].id, content="B1")
      inspect(evidence.cells[1].classification, content="unchanged")
    }
    None => abort("expected latest evidence")
  }
  app.dispose()
}

///|
test "AI context parity scenario covers edits, errors, formulas, deletes, and bounds" {
  let fixture = new_model_context_fixture()
  fixture.dispatch(SelectCell("A1"))
  fixture.dispatch(UpdateDraft("A1", "15"))
  fixture.dispatch(ApplySelected)
  let successful = fixture.snapshot(region=["A1"])
  inspect(successful.cells[0].result.status, content="ok")
  match successful.cells[0].result.value {
    Some(value) => {
      inspect(value.type_name, content="Int")
      inspect(value.value, content="15")
    }
    None => abort("expected successful Int value")
  }
  match successful.latest_trace {
    Some(trace) => inspect(trace.outcome, content="Ok(Int(15))")
    None => abort("expected successful trace")
  }
  match successful.latest_evidence {
    Some(evidence) => inspect(evidence.outcome, content="Ok(Int(15))")
    None => abort("expected successful evidence")
  }

  fixture.dispatch(UpdateDraft("A1", "oops"))
  fixture.dispatch(ApplySelected)
  let after_parse_error = fixture.snapshot(region=["A1"])
  inspect(after_parse_error.cells[0].result.status, content="ok")
  inspect(after_parse_error.cells[0].committed_text, content="15")
  inspect(after_parse_error.cells[0].draft_text, content="oops")
  inspect(after_parse_error.cells[0].draft_dirty, content="true")
  match after_parse_error.latest_trace {
    Some(trace) => inspect(trace.edit, content="A1 ← 15")
    None => abort("expected retained successful trace")
  }

  fixture.dispatch(SelectCell("B1"))
  fixture.dispatch(UpdateDraft("B1", "=A1 + 1"))
  fixture.dispatch(ApplySelected)
  let equivalent_context = fixture.snapshot(region=["B1"])
  match equivalent_context.cells[0].formula {
    Some(formula) =>
      match formula.shape {
        Some(shape) => inspect(shape, content="Add(Ref(A1), Literal(Int(1)))")
        None => abort("expected formula shape")
      }
    None => abort("expected formula metadata")
  }
  match equivalent_context.latest_evidence {
    Some(evidence) =>
      inspect(evidence.cells[0].classification, content="changed")
    None => abort("expected equivalent-formula evidence")
  }

  fixture.dispatch(SelectCell("A1"))
  fixture.dispatch(DeleteSelected)
  fixture.dispatch(SelectCell("B1"))
  let deleted_context = fixture.snapshot(region=["A1", "B1", "C1"], max_cells=1)
  inspect(deleted_context.truncated, content="true")
  debug_inspect(deleted_context.region, content="[\"B1\"]")
  inspect(deleted_context.cells[0].result.status, content="type_error")
  match deleted_context.latest_trace {
    Some(trace) => {
      inspect(trace.recomputed.length() <= 1, content="true")
      inspect(trace.changed.length() <= 1, content="true")
      inspect(trace.unchanged.length() <= 1, content="true")
    }
    None => abort("expected bounded delete trace")
  }
  match deleted_context.latest_evidence {
    Some(evidence) => {
      inspect(evidence.cells.length(), content="1")
      inspect(evidence.cells[0].id, content="A1")
      inspect(evidence.cells[0].after.status, content="missing")
    }
    None => abort("expected delete evidence")
  }
  fixture.dispose()
}

///|
test "incr_tea latest trace preserves operation outcome after selection" {
  let app = new_model_application()
  ignore(app.dispatch(SelectCell("A1")))
  ignore(app.dispatch(UpdateDraft("A1", "15")))
  ignore(app.dispatch(ApplySelected))
  let applied = app.observe().snapshot.ai_context
  let expected_outcome = match applied.latest_evidence {
    Some(evidence) => evidence.outcome
    None => abort("expected latest evidence after edit")
  }
  match applied.latest_trace {
    Some(trace) => inspect(trace.outcome == expected_outcome, content="true")
    None => abort("expected latest trace after edit")
  }
  ignore(app.dispatch(SelectCell("C1")))
  let selected = app.observe().snapshot.ai_context
  match selected.latest_trace {
    Some(trace) => inspect(trace.outcome == expected_outcome, content="true")
    None => abort("expected latest trace after selection")
  }
  app.dispose()
}
