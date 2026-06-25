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
    Some(td) => inspect(td.changed_str, content="[B1]")
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
