///|
/// Cross-root locality validation for the typed spreadsheet.
///
/// Mounts all 5 watched regions (grid, formula bar, status, trace, evidence)
/// sharing model state via per-region InputFields, dispatches messages through
/// `TypedSheetApplication`, and asserts its observed per-region patch/skip
/// counters.
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
/// Finds an observed region-stat entry by label. Aborts if not found.
#cfg(target="js")
fn row_by_label(
  stats : ReadOnlyArray[RegionRenderStats],
  label : String,
) -> RegionRenderStats {
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
  stats : ReadOnlyArray[RegionRenderStats],
  baseline : ReadOnlyArray[RegionRenderStats],
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
/// Creates a fresh TypedSheetApplication with 5 roots mounted on fake-DOM
/// hosts (ids `locality-formula`, -grid, -status, -trace, -evidence).
/// After mount each root has patch=1 (initial flush), skip=0.
/// Returns (app, baseline_region_stats).
#cfg(target="js")
fn setup_locality_test() -> (
  TypedSheetApplication,
  ReadOnlyArray[RegionRenderStats],
) {
  install_test_dom()
  create_locality_hosts()
  let app = match
    TypedSheetApplication::start(
      @incr.Runtime(),
      SheetStartMode::Standalone,
      AiContextPublisher::AiContextPublisher(_ => ()),
    ) {
    Ok(app) => app
    Err(_) => abort("standalone application failed to start")
  }
  let hosts = TypedSheetHosts::{
    grid: @tea.dom_get_element_by_id("locality-grid"),
    formula: @tea.dom_get_element_by_id("locality-formula"),
    status: @tea.dom_get_element_by_id("locality-status"),
    trace: @tea.dom_get_element_by_id("locality-trace"),
    evidence: @tea.dom_get_element_by_id("locality-evidence"),
  }
  match app.mount(hosts) {
    Ok(_) => ()
    Err(_) => abort("complete host cohort was rejected")
  }
  let baseline = app.observe().region_stats
  (app, baseline)
}

// ── Scenario 1: Cell value edit ───────────────────────────────────────

///|
#cfg(target="js")
test "locality: cell value edit — UpdateDraft + ApplySelected" {
  let (app, base) = setup_locality_test()

  ignore(app.dispatch(UpdateDraft("A1", "42")))
  let after_draft = match app.flush_presentation() {
    Ok(observation) => observation.region_stats
    Err(_) => abort("mounted presentation flush was rejected")
  }

  // UpdateDraft: grid/formula-bar patch (1), status/trace skip (1)
  check_delta(after_draft, base, "grid", 1, 0)
  check_delta(after_draft, base, "formula-bar", 1, 0)
  check_delta(after_draft, base, "status", 0, 1)
  check_delta(after_draft, base, "trace", 0, 1)
  check_delta(after_draft, base, "evidence", 0, 1)

  ignore(app.dispatch(ApplySelected))
  let after_apply = match app.flush_presentation() {
    Ok(observation) => observation.region_stats
    Err(_) => abort("mounted presentation flush was rejected")
  }

  // ApplySelected relative to after_draft: grid patches (1), formula-bar
  // skips (1), status patches (1), trace patches (1)
  check_delta(after_apply, after_draft, "grid", 1, 0)
  check_delta(after_apply, after_draft, "formula-bar", 0, 1)
  check_delta(after_apply, after_draft, "status", 1, 0)
  check_delta(after_apply, after_draft, "trace", 1, 0)
  check_delta(after_apply, after_draft, "evidence", 1, 0)

  app.dispose()
  restore_test_dom()
}

// ── Scenario 2: Selection only ────────────────────────────────────────

///|
#cfg(target="js")
test "locality: selection only — SelectCell" {
  let (app, base) = setup_locality_test()

  ignore(app.dispatch(SelectCell("A2")))
  let after = match app.flush_presentation() {
    Ok(observation) => observation.region_stats
    Err(_) => abort("mounted presentation flush was rejected")
  }

  // SelectCell: grid/formula-bar/status patch (1), trace skip (1)
  check_delta(after, base, "grid", 1, 0)
  check_delta(after, base, "formula-bar", 1, 0)
  check_delta(after, base, "status", 1, 0)
  check_delta(after, base, "trace", 0, 1)
  check_delta(after, base, "evidence", 0, 1)

  app.dispose()
  restore_test_dom()
}

// ── Scenario 3: Draft only (no commit) ────────────────────────────────

///|
#cfg(target="js")
test "locality: draft only — UpdateDraft without ApplySelected" {
  let (app, base) = setup_locality_test()

  ignore(app.dispatch(UpdateDraft("A1", "99")))
  let after = match app.flush_presentation() {
    Ok(observation) => observation.region_stats
    Err(_) => abort("mounted presentation flush was rejected")
  }

  // UpdateDraft: grid/formula-bar patch (1), status/trace skip (1)
  check_delta(after, base, "grid", 1, 0)
  check_delta(after, base, "formula-bar", 1, 0)
  check_delta(after, base, "status", 0, 1)
  check_delta(after, base, "trace", 0, 1)
  check_delta(after, base, "evidence", 0, 1)

  app.dispose()
  restore_test_dom()
}

// ── Scenario 4: Inline edit commit ────────────────────────────────────

///|
#cfg(target="js")
test "locality: inline edit commit — BeginInlineEdit + ApplyInlineEdit" {
  let (app, base) = setup_locality_test()

  ignore(app.dispatch(BeginInlineEdit("A1")))
  let after_begin = match app.flush_presentation() {
    Ok(observation) => observation.region_stats
    Err(_) => abort("mounted presentation flush was rejected")
  }

  // BeginInlineEdit: grid/formula-bar/status patch (1), trace skip (1)
  check_delta(after_begin, base, "grid", 1, 0)
  check_delta(after_begin, base, "formula-bar", 1, 0)
  check_delta(after_begin, base, "status", 1, 0)
  check_delta(after_begin, base, "trace", 0, 1)
  check_delta(after_begin, base, "evidence", 0, 1)

  ignore(app.dispatch(ApplyInlineEdit("A1")))
  let after_apply = match app.flush_presentation() {
    Ok(observation) => observation.region_stats
    Err(_) => abort("mounted presentation flush was rejected")
  }

  // ApplyInlineEdit relative to after_begin: grid patches (1), formula-bar
  // skips (1), status patches (1), trace patches (1)
  check_delta(after_apply, after_begin, "grid", 1, 0)
  check_delta(after_apply, after_begin, "formula-bar", 0, 1)
  check_delta(after_apply, after_begin, "status", 1, 0)
  check_delta(after_apply, after_begin, "trace", 1, 0)
  check_delta(after_apply, after_begin, "evidence", 1, 0)

  app.dispose()
  restore_test_dom()
}
