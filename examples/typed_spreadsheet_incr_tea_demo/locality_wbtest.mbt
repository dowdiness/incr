///|
/// Cross-root locality validation for the typed spreadsheet.
///
/// Mounts all 5 watched regions (grid, formula bar, status, trace, evidence)
/// sharing model state via per-region InputFields, dispatches messages through
/// the shared update handler, and asserts per-root patch/skip counters via
/// `BrowserRenderer::root_stats()`.
///
/// Each test installs a fresh fake DOM, mounts 5 roots on `div` host
/// elements, and verifies per-root deltas for one operation sequence.
/// Assertions are delta-based (from a saved baseline snapshot), so tests
/// survive changes to mount flush behavior.

// ── Fake DOM shim ─────────────────────────────────────────────────────
// Forked from incr_tea/renderer_wbtest.mbt's test_install_focus_dom.
// The two packages can't share a wbtest-visible helper, so this copy lives
// here. Keep in sync when adding Element/TextNode members.

#cfg(target="js")
extern "js" fn install_test_dom() -> Unit =
  #| () => {
  #|   const byId = new Map();
  #|   globalThis.__prevDocument = globalThis.document;
  #|   globalThis.__prevWindow = globalThis.window;
  #|   globalThis.__rafQueue = [];
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
  #|       this.attributes.set(name, String(value));
  #|       if (name === "id") byId.set(String(value), this);
  #|     }
  #|     removeAttribute(name) {
  #|       if (name === "id") byId.delete(this.attributes.get(name));
  #|       this.attributes.delete(name);
  #|     }
  #|     addEventListener(name, listener) { this.listeners.set(name, listener); }
  #|     querySelector(selector) {
  #|       return selector.startsWith("#") ? (byId.get(selector.slice(1)) ?? null) : null;
  #|     }
  #|   }
  #|   globalThis.document = {
  #|     createElement(tag) { return new Element(tag); },
  #|     createTextNode(value) { return new TextNode(value); },
  #|     getElementById(id) { return byId.get(String(id)) ?? null; },
  #|   };
  #|   globalThis.window = {
  #|     requestAnimationFrame(callback) {
  #|       globalThis.__rafQueue.push(callback);
  #|       return globalThis.__rafQueue.length;
  #|     },
  #|   };
  #| }

///|
/// Creates 5 host `div` elements with fixed ids and registers them in
/// the fake DOM so `dom_get_element_by_id` can find them.
/// The fake DOM's `getElementById` reads from an internal `byId` map
/// populated by `setAttribute("id", ...)` — tree membership is not
/// required, so the hosts are never appended to a parent.
#cfg(target="js")
extern "js" fn create_locality_hosts() -> Unit =
  #| () => {
  #|   const ids = ["locality-formula", "locality-grid", "locality-status", "locality-trace", "locality-evidence"];
  #|   for (const id of ids) {
  #|     const el = globalThis.document.createElement("div");
  #|     el.setAttribute("id", id);
  #|   }
  #| }

///|
/// Restores global document and window after a test.
#cfg(target="js")
extern "js" fn restore_test_dom() -> Unit =
  #| () => {
  #|   globalThis.document = globalThis.__prevDocument;
  #|   globalThis.window = globalThis.__prevWindow;
  #|   delete globalThis.__prevDocument;
  #|   delete globalThis.__prevWindow;
  #|   delete globalThis.__rafQueue;
  #| }

// ── Test helpers ──────────────────────────────────────────────────────

///|
/// Finds a root_stats entry by label. Aborts if not found.
#cfg(target="js")
fn row_by_label(
  stats : Array[@tea.RootStats],
  label : String,
) -> @tea.RootStats {
  let ix = stats.search_by(row => row.label == label)
  guard ix is Some(i) else {
    abort("root \"\{label}\" not found in root_stats")
  }
  stats[i]
}

///|
/// Asserts per-root patch/skip delta from a baseline snapshot.
/// Checks the DIFFERENCE between `stats` and `baseline`, not the
/// cumulative values — so tests survive changes to mount flush behavior.
#cfg(target="js")
fn check_delta(
  stats : Array[@tea.RootStats],
  baseline : Array[@tea.RootStats],
  label : String,
  patch_delta : Int,
  skip_delta : Int,
) -> Unit {
  let row = row_by_label(stats, label)
  let base_row = row_by_label(baseline, label)
  let actual_patch = row.patch_attempts - base_row.patch_attempts
  let actual_skip = row.skipped_patches - base_row.skipped_patches
  guard actual_patch == patch_delta && actual_skip == skip_delta else {
    abort(
      "root \"\{label}\": expected delta patch=\{patch_delta}, skip=\{skip_delta}; got delta patch=\{actual_patch}, skip=\{actual_skip}",
    )
  }
}

// ── Shared test setup ─────────────────────────────────────────────────

///|
/// Creates a fresh TypedSheetApp + BrowserRenderer with 5 roots mounted on
/// fake-DOM hosts (ids `locality-formula`, -grid, -status, -trace, -evidence).
/// After mount each root has patch=1 (initial flush), skip=0.
/// Returns (renderer, app, baseline_root_stats).
#cfg(target="js")
fn setup_locality_test() -> (
  @tea.BrowserRenderer[Msg],
  TypedSheetApp,
  Array[@tea.RootStats],
) {
  install_test_dom()
  create_locality_hosts()
  let host_formula = @tea.dom_get_element_by_id("locality-formula")
  let host_grid = @tea.dom_get_element_by_id("locality-grid")
  let host_status = @tea.dom_get_element_by_id("locality-status")
  let host_trace = @tea.dom_get_element_by_id("locality-trace")
  let host_evidence = @tea.dom_get_element_by_id("locality-evidence")
  let runtime = @incr.Runtime()
  let app = TypedSheetApp(runtime)
  let renderer = @tea.BrowserRenderer::BrowserRenderer(runtime)
  ignore(renderer.mount(host_formula, app.prog_formula, label="formula-bar"))
  ignore(renderer.mount(host_grid, app.prog_grid, label="grid"))
  ignore(renderer.mount(host_status, app.prog_status, label="status"))
  ignore(renderer.mount(host_trace, app.prog_trace, label="trace"))
  ignore(renderer.mount(host_evidence, app.prog_evidence, label="evidence"))
  let baseline = renderer.root_stats()
  (renderer, app, baseline)
}

// ── Scenario 1: Cell value edit ───────────────────────────────────────

///|
#cfg(target="js")
test "locality: cell value edit — UpdateDraft + ApplySelected" {
  let (renderer, app, base) = setup_locality_test()

  ignore(app.prog_grid.dispatch(UpdateDraft("A1", "42")))
  renderer.flush_all()
  let after_draft = renderer.root_stats()

  // UpdateDraft: grid/formula-bar patch (1), status/trace skip (1)
  check_delta(after_draft, base, "grid", 1, 0)
  check_delta(after_draft, base, "formula-bar", 1, 0)
  check_delta(after_draft, base, "status", 0, 1)
  check_delta(after_draft, base, "trace", 0, 1)
  check_delta(after_draft, base, "evidence", 0, 1)

  ignore(app.prog_grid.dispatch(ApplySelected))
  renderer.flush_all()
  let after_apply = renderer.root_stats()

  // ApplySelected relative to after_draft: grid patches (1), formula-bar
  // skips (1), status patches (1), trace patches (1)
  check_delta(after_apply, after_draft, "grid", 1, 0)
  check_delta(after_apply, after_draft, "formula-bar", 0, 1)
  check_delta(after_apply, after_draft, "status", 1, 0)
  check_delta(after_apply, after_draft, "trace", 1, 0)
  check_delta(after_apply, after_draft, "evidence", 1, 0)

  renderer.dispose()
  restore_test_dom()
}

// ── Scenario 2: Selection only ────────────────────────────────────────

///|
#cfg(target="js")
test "locality: selection only — SelectCell" {
  let (renderer, app, base) = setup_locality_test()

  ignore(app.prog_grid.dispatch(SelectCell("A2")))
  renderer.flush_all()
  let after = renderer.root_stats()

  // SelectCell: grid/formula-bar/status patch (1), trace skip (1)
  check_delta(after, base, "grid", 1, 0)
  check_delta(after, base, "formula-bar", 1, 0)
  check_delta(after, base, "status", 1, 0)
  check_delta(after, base, "trace", 0, 1)
  check_delta(after, base, "evidence", 0, 1)

  renderer.dispose()
  restore_test_dom()
}

// ── Scenario 3: Draft only (no commit) ────────────────────────────────

///|
#cfg(target="js")
test "locality: draft only — UpdateDraft without ApplySelected" {
  let (renderer, app, base) = setup_locality_test()

  ignore(app.prog_grid.dispatch(UpdateDraft("A1", "99")))
  renderer.flush_all()
  let after = renderer.root_stats()

  // UpdateDraft: grid/formula-bar patch (1), status/trace skip (1)
  check_delta(after, base, "grid", 1, 0)
  check_delta(after, base, "formula-bar", 1, 0)
  check_delta(after, base, "status", 0, 1)
  check_delta(after, base, "trace", 0, 1)
  check_delta(after, base, "evidence", 0, 1)

  renderer.dispose()
  restore_test_dom()
}

// ── Scenario 4: Inline edit commit ────────────────────────────────────

///|
#cfg(target="js")
test "locality: inline edit commit — BeginInlineEdit + ApplyInlineEdit" {
  let (renderer, app, base) = setup_locality_test()

  ignore(app.prog_grid.dispatch(BeginInlineEdit("A1")))
  renderer.flush_all()
  let after_begin = renderer.root_stats()

  // BeginInlineEdit: grid/formula-bar/status patch (1), trace skip (1)
  check_delta(after_begin, base, "grid", 1, 0)
  check_delta(after_begin, base, "formula-bar", 1, 0)
  check_delta(after_begin, base, "status", 1, 0)
  check_delta(after_begin, base, "trace", 0, 1)
  check_delta(after_begin, base, "evidence", 0, 1)

  ignore(app.prog_grid.dispatch(ApplyInlineEdit("A1")))
  renderer.flush_all()
  let after_apply = renderer.root_stats()

  // ApplyInlineEdit relative to after_begin: grid patches (1), formula-bar
  // skips (1), status patches (1), trace patches (1)
  check_delta(after_apply, after_begin, "grid", 1, 0)
  check_delta(after_apply, after_begin, "formula-bar", 0, 1)
  check_delta(after_apply, after_begin, "status", 1, 0)
  check_delta(after_apply, after_begin, "trace", 1, 0)
  check_delta(after_apply, after_begin, "evidence", 1, 0)

  renderer.dispose()
  restore_test_dom()
}
