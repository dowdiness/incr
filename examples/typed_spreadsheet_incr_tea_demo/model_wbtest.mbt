///|
struct ModelSnapshot {
  sheet : @typed_spreadsheet.Worksheet
  cells : Array[String]
  drafts : Array[CellDraft]
  selected_cell : String
  editing_cell : String?
  trace_data : TraceData?
  last_edit : String
  status : String
}

///|
fn SheetState::peek_model(self : SheetState) -> ModelSnapshot {
  {
    sheet: self.sheet,
    cells: self.cells.peek(),
    drafts: self.drafts.peek(),
    selected_cell: self.selected_cell.peek(),
    editing_cell: self.editing_cell.peek(),
    trace_data: self.trace.peek(),
    last_edit: self.last_edit.peek(),
    status: self.status.peek(),
  }
}

///|
fn draft_for(model : ModelSnapshot, cell : String) -> String {
  draft_text_from(model.drafts, cell)
}

///|
fn cell_id(model : ModelSnapshot, cell : String) -> @typed_spreadsheet.CellId {
  cell_id_from_sheet(model.sheet, cell)
}

///|
fn TypedSheetApp::dispose(self : TypedSheetApp) -> Unit {
  self._state.val.sheet.dispose()
  self.prog_grid.dispose()
  self.prog_formula.dispose()
  self.prog_status.dispose()
  self.prog_trace.dispose()
  self.prog_evidence.dispose()
  self._state.val._scope.dispose()
}

///|
test "incr_tea spreadsheet proof starts with seeded representative grid" {
  let app = TypedSheetApp(@incr.Runtime())
  let model = app._state.val.peek_model()

  inspect(model.selected_cell, content="B1")
  inspect(model.cells.length(), content="2500")
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
    Some(td) => inspect(td.changed_str, content="[B1]")
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
  let app = TypedSheetApp(@incr.Runtime())
  let before = app._state.val.peek_model()
  let initial_status = before.status

  // UpdateDraft writes only selected_cell + drafts — status must stay unchanged
  ignore(app.prog_grid.dispatch(UpdateDraft("C1", "99")))
  let after_draft = app._state.val.peek_model()
  inspect(after_draft.status, content=initial_status)

  // UseExample is also draft-only — status must stay unchanged
  ignore(app.prog_grid.dispatch(UseExample("42")))
  let after_example = app._state.val.peek_model()
  inspect(after_example.status, content=initial_status)

  // SelectCell still patches status (selection is not draft-only)
  ignore(app.prog_grid.dispatch(SelectCell("A1")))
  let after_select = app._state.val.peek_model()
  inspect(after_select.status, content="Selected A1.")

  app.dispose()
}

// ── Cross-root locality: DOM/RAF shims ──────────────────────────
// These set up a fake `document`/`window` for mount/flush without a
// real browser. They manipulate the same `globalThis.__incrTea*` state
// as the incr_tea wbtest helpers.

///|
#cfg(target="js")
extern "js" fn typed_sheet_test_setup_dom() -> @tea.DomElement =
  #| () => {
  #|   const byId = new Map();
  #|   globalThis.__incrTeaPreviousDocument = globalThis.document;
  #|   globalThis.__incrTeaPreviousWindow = globalThis.window;
  #|   globalThis.__incrTeaFocusedId = "";
  #|   globalThis.__incrTeaSelectedId = "";
  #|   globalThis.__incrTeaRafs = [];
  #|   class TextNode {
  #|     constructor(value) { this.nodeValue = String(value); this.parentNode = null; }
  #|   }
  #|   class Element {
  #|     constructor(tag) {
  #|       this.tagName = String(tag).toUpperCase();
  #|       this.children = [];
  #|       this.parentNode = null;
  #|       this.attributes = new Map();
  #|       this.listeners = new Map();
  #|       this.value = "";
  #|     }
  #|     appendChild(child) {
  #|       if (child.parentNode) child.parentNode.removeChild(child);
  #|       this.children.push(child);
  #|       child.parentNode = this;
  #|     }
  #|     replaceChildren(child) {
  #|       for (const old of this.children) old.parentNode = null;
  #|       this.children = [];
  #|       if (child) this.appendChild(child);
  #|     }
  #|     replaceChild(next, old) {
  #|       const index = this.children.indexOf(old);
  #|       if (index < 0) throw new Error("old child missing");
  #|       if (next.parentNode) next.parentNode.removeChild(next);
  #|       old.parentNode = null;
  #|       this.children[index] = next;
  #|       next.parentNode = this;
  #|     }
  #|     removeChild(child) {
  #|       const index = this.children.indexOf(child);
  #|       if (index >= 0) this.children.splice(index, 1);
  #|       child.parentNode = null;
  #|     }
  #|     setAttribute(name, value) {
  #|       const stringValue = String(value);
  #|       this.attributes.set(name, stringValue);
  #|       if (name === "id") byId.set(stringValue, this);
  #|     }
  #|     removeAttribute(name) {
  #|       if (name === "id") byId.delete(this.attributes.get(name));
  #|       this.attributes.delete(name);
  #|     }
  #|     addEventListener(name, listener) { this.listeners.set(name, listener); }
  #|     querySelector(selector) {
  #|       return selector.startsWith("#") ? (byId.get(selector.slice(1)) ?? null) : null;
  #|     }
  #|     focus() { globalThis.__incrTeaFocusedId = this.attributes.get("id") ?? ""; }
  #|     select() { globalThis.__incrTeaSelectedId = this.attributes.get("id") ?? ""; }
  #|   }
  #|   globalThis.document = {
  #|     createElement(tag) { return new Element(tag); },
  #|     createTextNode(value) { return new TextNode(value); },
  #|     getElementById(id) { return byId.get(String(id)) ?? null; },
  #|   };
  #|   globalThis.window = {
  #|     requestAnimationFrame(callback) {
  #|       globalThis.__incrTeaRafs.push(callback);
  #|       return globalThis.__incrTeaRafs.length;
  #|     },
  #|   };
  #|   return new Element("host");
  #| }

///|
#cfg(target="js")
extern "js" fn typed_sheet_test_run_raf() -> Unit =
  #| () => {
  #|   const callback = globalThis.__incrTeaRafs.shift();
  #|   if (!callback) throw new Error("missing queued rAF");
  #|   callback();
  #| }

///|
#cfg(target="js")
extern "js" fn typed_sheet_test_create_host() -> @tea.DomElement =
  #| () => document.createElement("div")

///|
#cfg(target="js")
extern "js" fn typed_sheet_test_restore_dom() -> Unit =
  #| () => {
  #|   if (globalThis.__incrTeaPreviousDocument === undefined) {
  #|     delete globalThis.document;
  #|   } else {
  #|     globalThis.document = globalThis.__incrTeaPreviousDocument;
  #|   }
  #|   if (globalThis.__incrTeaPreviousWindow === undefined) {
  #|     delete globalThis.window;
  #|   } else {
  #|     globalThis.window = globalThis.__incrTeaPreviousWindow;
  #|   }
  #|   delete globalThis.__incrTeaPreviousDocument;
  #|   delete globalThis.__incrTeaPreviousWindow;
  #|   delete globalThis.__incrTeaRafs;
  #| }

// ── Cross-root locality: helpers ─────────────────────────────────

///|
#cfg(target="js")
fn find_by_label(
  stats : Array[@tea.RootStats],
  label : String,
) -> @tea.RootStats {
  match stats.search_by(s => s.label == label) {
    Some(i) => stats[i]
    None => abort("missing root: \{label}")
  }
}

///|
#cfg(target="js")
fn delta_patch_attempts(
  after : Array[@tea.RootStats],
  before : Array[@tea.RootStats],
  label : String,
) -> Int {
  find_by_label(after, label).patch_attempts -
  find_by_label(before, label).patch_attempts
}

///|
#cfg(target="js")
fn delta_skipped_patches(
  after : Array[@tea.RootStats],
  before : Array[@tea.RootStats],
  label : String,
) -> Int {
  find_by_label(after, label).skipped_patches -
  find_by_label(before, label).skipped_patches
}

///|
#cfg(target="js")
fn mount_all_roots(
  renderer : @tea.BrowserRenderer[Msg],
  app : TypedSheetApp,
) -> Unit {
  ignore(
    renderer.mount(typed_sheet_test_create_host(), app.prog_grid, label="grid"),
  )
  ignore(
    renderer.mount(
      typed_sheet_test_create_host(),
      app.prog_formula,
      label="formula-bar",
    ),
  )
  ignore(
    renderer.mount(
      typed_sheet_test_create_host(),
      app.prog_status,
      label="status",
    ),
  )
  ignore(
    renderer.mount(
      typed_sheet_test_create_host(),
      app.prog_trace,
      label="trace",
    ),
  )
  ignore(
    renderer.mount(
      typed_sheet_test_create_host(),
      app.prog_evidence,
      label="evidence",
    ),
  )
}

// ── Cross-root locality: 5 validation tests ─────────────────────

///|
#cfg(target="js")
test "cross-root locality: selection-only patches grid, formula, status" {
  let _host = typed_sheet_test_setup_dom()
  let runtime = @incr.Runtime()
  let app = TypedSheetApp(runtime)
  let renderer : @tea.BrowserRenderer[Msg] = @tea.BrowserRenderer::BrowserRenderer(
    runtime,
  )
  mount_all_roots(renderer, app)
  let before = renderer.root_stats()

  ignore(app.prog_grid.dispatch(SelectCell("A2")))
  typed_sheet_test_run_raf()

  let after = renderer.root_stats()
  inspect(delta_patch_attempts(after, before, "grid"), content="1")
  inspect(delta_skipped_patches(after, before, "grid"), content="0")
  inspect(delta_patch_attempts(after, before, "formula-bar"), content="1")
  inspect(delta_skipped_patches(after, before, "formula-bar"), content="0")
  inspect(delta_patch_attempts(after, before, "status"), content="1")
  inspect(delta_skipped_patches(after, before, "status"), content="0")
  inspect(delta_patch_attempts(after, before, "trace"), content="0")
  inspect(delta_skipped_patches(after, before, "trace"), content="1")

  renderer.dispose()
  app.dispose()
  typed_sheet_test_restore_dom()
}

///|
#cfg(target="js")
test "cross-root locality: draft-only patches grid, formula" {
  let _host = typed_sheet_test_setup_dom()
  let runtime = @incr.Runtime()
  let app = TypedSheetApp(runtime)
  let renderer : @tea.BrowserRenderer[Msg] = @tea.BrowserRenderer::BrowserRenderer(
    runtime,
  )
  mount_all_roots(renderer, app)
  let before = renderer.root_stats()

  ignore(app.prog_grid.dispatch(UpdateDraft("C1", "99")))
  typed_sheet_test_run_raf()

  let after = renderer.root_stats()
  inspect(delta_patch_attempts(after, before, "grid"), content="1")
  inspect(delta_skipped_patches(after, before, "grid"), content="0")
  inspect(delta_patch_attempts(after, before, "formula-bar"), content="1")
  inspect(delta_skipped_patches(after, before, "formula-bar"), content="0")
  inspect(delta_patch_attempts(after, before, "status"), content="0")
  inspect(delta_skipped_patches(after, before, "status"), content="1")
  inspect(delta_patch_attempts(after, before, "trace"), content="0")
  inspect(delta_skipped_patches(after, before, "trace"), content="1")

  renderer.dispose()
  app.dispose()
  typed_sheet_test_restore_dom()
}

///|
#cfg(target="js")
test "cross-root locality: apply after draft patches grid, status, trace; formula skips" {
  let _host = typed_sheet_test_setup_dom()
  let runtime = @incr.Runtime()
  let app = TypedSheetApp(runtime)
  let renderer : @tea.BrowserRenderer[Msg] = @tea.BrowserRenderer::BrowserRenderer(
    runtime,
  )
  mount_all_roots(renderer, app)

  // Prime: set draft and flush so last_view captures draft state
  ignore(app.prog_grid.dispatch(UpdateDraft("A1", "42")))
  typed_sheet_test_run_raf()

  let before = renderer.root_stats()

  // Act: apply the draft — committed changes but formula-bar inputs stay
  ignore(app.prog_grid.dispatch(ApplySelected))
  typed_sheet_test_run_raf()

  let after = renderer.root_stats()
  inspect(delta_patch_attempts(after, before, "grid"), content="1")
  inspect(delta_skipped_patches(after, before, "grid"), content="0")
  inspect(delta_patch_attempts(after, before, "formula-bar"), content="0")
  inspect(delta_skipped_patches(after, before, "formula-bar"), content="1")
  inspect(delta_patch_attempts(after, before, "status"), content="1")
  inspect(delta_skipped_patches(after, before, "status"), content="0")
  inspect(delta_patch_attempts(after, before, "trace"), content="1")
  inspect(delta_skipped_patches(after, before, "trace"), content="0")

  renderer.dispose()
  app.dispose()
  typed_sheet_test_restore_dom()
}

///|
#cfg(target="js")
test "cross-root locality: begin-inline-edit patches grid, formula, status" {
  let _host = typed_sheet_test_setup_dom()
  let runtime = @incr.Runtime()
  let app = TypedSheetApp(runtime)
  let renderer : @tea.BrowserRenderer[Msg] = @tea.BrowserRenderer::BrowserRenderer(
    runtime,
  )
  mount_all_roots(renderer, app)
  let before = renderer.root_stats()

  ignore(app.prog_grid.dispatch(BeginInlineEdit("D1")))
  typed_sheet_test_run_raf()

  let after = renderer.root_stats()
  inspect(delta_patch_attempts(after, before, "grid"), content="1")
  inspect(delta_skipped_patches(after, before, "grid"), content="0")
  inspect(delta_patch_attempts(after, before, "formula-bar"), content="1")
  inspect(delta_skipped_patches(after, before, "formula-bar"), content="0")
  inspect(delta_patch_attempts(after, before, "status"), content="1")
  inspect(delta_skipped_patches(after, before, "status"), content="0")
  inspect(delta_patch_attempts(after, before, "trace"), content="0")
  inspect(delta_skipped_patches(after, before, "trace"), content="1")

  renderer.dispose()
  app.dispose()
  typed_sheet_test_restore_dom()
}

///|
#cfg(target="js")
test "cross-root locality: clean apply patches only status and trace" {
  let _host = typed_sheet_test_setup_dom()
  let runtime = @incr.Runtime()
  let app = TypedSheetApp(runtime)
  let renderer : @tea.BrowserRenderer[Msg] = @tea.BrowserRenderer::BrowserRenderer(
    runtime,
  )
  mount_all_roots(renderer, app)

  // Prime: select A1 so ApplySelected targets it
  ignore(app.prog_grid.dispatch(SelectCell("A1")))
  typed_sheet_test_run_raf()

  let before = renderer.root_stats()

  // Act: apply the same value — nothing in grid/formula-bar read-sets changes
  ignore(app.prog_grid.dispatch(ApplySelected))
  typed_sheet_test_run_raf()

  let after = renderer.root_stats()
  inspect(delta_patch_attempts(after, before, "grid"), content="0")
  inspect(delta_skipped_patches(after, before, "grid"), content="1")
  inspect(delta_patch_attempts(after, before, "formula-bar"), content="0")
  inspect(delta_skipped_patches(after, before, "formula-bar"), content="1")
  inspect(delta_patch_attempts(after, before, "status"), content="1")
  inspect(delta_skipped_patches(after, before, "status"), content="0")
  inspect(delta_patch_attempts(after, before, "trace"), content="1")
  inspect(delta_skipped_patches(after, before, "trace"), content="0")

  renderer.dispose()
  app.dispose()
  typed_sheet_test_restore_dom()
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
  let app = TypedSheetApp(@incr.Runtime())
  ignore(app.prog_grid.dispatch(SelectCell("AX50")))
  ignore(app.prog_grid.dispatch(MoveSelection(1, 0)))
  inspect(app._state.val.selected_cell.peek(), content="AX50")
  ignore(app.prog_grid.dispatch(MoveSelection(0, 1)))
  inspect(app._state.val.selected_cell.peek(), content="AX50")
  ignore(app.prog_grid.dispatch(SelectCell("A1")))
  ignore(app.prog_grid.dispatch(MoveSelection(-1, 0)))
  inspect(app._state.val.selected_cell.peek(), content="A1")
  ignore(app.prog_grid.dispatch(MoveSelection(0, -1)))
  inspect(app._state.val.selected_cell.peek(), content="A1")
  app.dispose()
}

///|
test "incr_tea AI context stays schema-versioned and bounded" {
  let app = TypedSheetApp(@incr.Runtime())
  let context = app._state.val.ai_context_snapshot(
    region?=Some(["A1", "B1", "C1"]),
    max_cells=2,
  )
  inspect(context.schema_version, content="1")
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
  app.dispose()
}

///|
test "incr_tea AI context carries latest trace and evidence" {
  let app = TypedSheetApp(@incr.Runtime())
  ignore(app.prog_grid.dispatch(SelectCell("A1")))
  ignore(app.prog_grid.dispatch(UpdateDraft("A1", "15")))
  ignore(app.prog_grid.dispatch(ApplySelected))
  let context = app._state.val.ai_context_snapshot()
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
      inspect(edited.before_result_status, content="ok")
      inspect(edited.before_result, content="Ok(Int(10))")
      inspect(edited.after_kind, content="input")
      inspect(edited.after_result_status, content="ok")
      inspect(edited.after_result, content="Ok(Int(15))")
      let dependent = evidence.cells[1]
      inspect(dependent.id, content="B1")
      inspect(dependent.classification, content="changed")
      inspect(dependent.before_kind, content="formula")
      inspect(dependent.before_result_status, content="ok")
      inspect(dependent.before_result, content="Ok(Int(11))")
      inspect(dependent.after_kind, content="formula")
      inspect(dependent.after_result_status, content="ok")
      inspect(dependent.after_result, content="Ok(Int(16))")
    }
    None => abort("expected latest evidence")
  }
  ignore(app.prog_grid.dispatch(ResetSheet))
  let reset_context = app._state.val.ai_context_snapshot()
  inspect(reset_context.selected_cell, content="B1")
  inspect(reset_context.latest_trace is None, content="true")
  inspect(reset_context.latest_evidence is None, content="true")
  app.dispose()
}

///|
test "incr_tea evidence capture stays bounded for many direct dependents" {
  let app = TypedSheetApp(@incr.Runtime())
  for row in 2..<=20 {
    let cell = "B\{row}"
    ignore(app.prog_grid.dispatch(SelectCell(cell)))
    ignore(app.prog_grid.dispatch(UpdateDraft(cell, "=A1")))
    ignore(app.prog_grid.dispatch(ApplySelected))
  }
  let ids = state_capture_cell_ids(app._state, state_cell_id(app._state, "A1"))
  inspect(ids.length(), content="16")
  inspect(@demo.cell_id_to_string(ids[0]), content="A1")
  inspect(@demo.cell_id_to_string(ids[1]), content="B20")
  inspect(@demo.cell_id_to_string(ids[2]), content="B1")
  inspect(@demo.cell_id_to_string(ids[15]), content="B14")
  let selected_id = state_cell_id(app._state, "B20")
  let mut selected_count = 0
  for id in ids {
    if id == selected_id {
      selected_count += 1
    }
  }
  inspect(selected_count, content="1")
  app.dispose()
}

///|
test "incr_tea evidence distinguishes unchanged formula recomputation" {
  let app = TypedSheetApp(@incr.Runtime())
  ignore(app.prog_grid.dispatch(SelectCell("B1")))
  ignore(app.prog_grid.dispatch(UpdateDraft("B1", "=A1 * 0")))
  ignore(app.prog_grid.dispatch(ApplySelected))
  ignore(app.prog_grid.dispatch(SelectCell("A1")))
  ignore(app.prog_grid.dispatch(UpdateDraft("A1", "15")))
  ignore(app.prog_grid.dispatch(ApplySelected))
  let context = app._state.val.ai_context_snapshot()
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
test "incr_tea latest trace preserves operation outcome after selection" {
  let app = TypedSheetApp(@incr.Runtime())
  ignore(app.prog_grid.dispatch(SelectCell("A1")))
  ignore(app.prog_grid.dispatch(UpdateDraft("A1", "15")))
  ignore(app.prog_grid.dispatch(ApplySelected))
  let applied = app._state.val.ai_context_snapshot()
  let expected_outcome = match applied.latest_evidence {
    Some(evidence) => evidence.outcome
    None => abort("expected latest evidence after edit")
  }
  match applied.latest_trace {
    Some(trace) => inspect(trace.outcome == expected_outcome, content="true")
    None => abort("expected latest trace after edit")
  }
  ignore(app.prog_grid.dispatch(SelectCell("C1")))
  let selected = app._state.val.ai_context_snapshot()
  match selected.latest_trace {
    Some(trace) => inspect(trace.outcome == expected_outcome, content="true")
    None => abort("expected latest trace after selection")
  }
  app.dispose()
}
