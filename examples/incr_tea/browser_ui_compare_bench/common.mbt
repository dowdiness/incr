///|
/// Rabbita and Luna half of the adjacent-framework mounted browser benchmark.
/// The package is JS-only so the root `examples/incr_tea` package remains
/// wasm-gc benchable.

///|
priv enum UiCompareCounterOperation {
  UiCompareInitialMount
  UiCompareDisplayedCount
  UiCompareUnrelated
}

///|
priv enum UiCompareKeyedListOperation {
  UiCompareListPrepend
  UiCompareListRemoveFirst
  UiCompareListReverse
}

///|
priv enum UiComparePanelOperation {
  UiCompareHiddenUpdate
  UiCompareOpen
  UiCompareVisibleUpdate
  UiCompareClose
}

///|
extern "js" fn ui_compare_now_ms() -> Double =
  #| () => performance.now()

///|
extern "js" fn ui_compare_create_host() -> @js_dom.Element =
  #| () => {
  #|   const host = document.createElement("div");
  #|   const next = (globalThis.__incrTeaUiCompareHostSeq ?? 0) + 1;
  #|   globalThis.__incrTeaUiCompareHostSeq = next;
  #|   host.id = `incr-tea-ui-compare-host-${next}`;
  #|   host.className = "incr-tea-ui-compare-host";
  #|   host.style.cssText = [
  #|     "position:absolute",
  #|     "left:-10000px",
  #|     "top:0",
  #|     "width:960px",
  #|     "contain:content",
  #|     "visibility:hidden",
  #|   ].join(";");
  #|   document.body.appendChild(host);
  #|   return host;
  #| }

///|
extern "js" fn ui_compare_host_id(host : @js_dom.Element) -> String =
  #| (host) => host.id

///|
extern "js" fn ui_compare_remove_host(host : @js_dom.Element) -> Unit =
  #| (host) => { host.remove(); }

///|
extern "js" fn ui_compare_click_action(
  host : @js_dom.Element,
  action : String,
) -> Unit =
  #| (host, action) => {
  #|   const selector = `[data-bench-action="${CSS.escape(action)}"]`;
  #|   const button = host.querySelector(selector);
  #|   if (!button) throw new Error(`missing benchmark action ${action}`);
  #|   button.click();
  #| }

///|
extern "js" fn ui_compare_try_click_action(
  host : @js_dom.Element,
  action : String,
) -> Bool =
  #| (host, action) => {
  #|   const selector = `[data-bench-action="${CSS.escape(action)}"]`;
  #|   const button = host.querySelector(selector);
  #|   if (!button) return false;
  #|   button.click();
  #|   return true;
  #| }

///|
extern "js" fn ui_compare_install_adjacent_api(
  run : (String, String, String, Int, Int, Int) -> String,
) -> Unit =
  #| (run) => {
  #|   const toInt = (value, fallback) => {
  #|     const parsed = Number(value);
  #|     return Number.isFinite(parsed) ? Math.trunc(parsed) : fallback;
  #|   };
  #|   const api = globalThis.__incrTeaUiCompareDomBench ?? {};
  #|   api.runAdjacentCell = (system, suite, operation, n = 0, iterations = 200, samples = 9) => JSON.parse(run(
  #|     String(system),
  #|     String(suite),
  #|     String(operation),
  #|     toInt(n, 0),
  #|     toInt(iterations, 200),
  #|     toInt(samples, 9),
  #|   ));
  #|   api.runAdjacent = (system, operation, iterations = 200, samples = 9) => api.runAdjacentCell(
  #|     system,
  #|     "counter",
  #|     operation,
  #|     0,
  #|     iterations,
  #|     samples,
  #|   );
  #|   api.runCell = (system, suite, operation, n = 0, iterations = 200, samples = 9) => {
  #|     const key = String(system);
  #|     if (key === "incr_tea" && api.runIncrTeaCell) {
  #|       return api.runIncrTeaCell(suite, operation, n, iterations, samples);
  #|     }
  #|     if (api.runAdjacentCell) {
  #|       return api.runAdjacentCell(key, suite, operation, n, iterations, samples);
  #|     }
  #|     throw new Error(`UI compare benchmark API is not installed: ${key}`);
  #|   };
  #|   api.run = (system, operation, iterations = 200, samples = 9) => api.runCell(
  #|     system,
  #|     "counter",
  #|     operation,
  #|     0,
  #|     iterations,
  #|     samples,
  #|   );
  #|   globalThis.__incrTeaUiCompareDomBench = api;
  #| }

///|
fn ui_compare_positive(value : Int, fallback : Int) -> Int {
  guard value > 0 else { fallback }
  value
}

///|
fn ui_compare_counter_operation(
  operation : String,
) -> UiCompareCounterOperation {
  match operation {
    "mount" | "initial-mount" | "initial_mount" => UiCompareInitialMount
    "displayed" | "displayed-count" | "displayed_count" =>
      UiCompareDisplayedCount
    "unrelated" | "unrelated-update" | "unrelated_update" => UiCompareUnrelated
    _ => abort("unknown UI compare counter operation: \{operation}")
  }
}

///|
fn UiCompareCounterOperation::name(self : UiCompareCounterOperation) -> String {
  match self {
    UiCompareInitialMount => "initial-mount"
    UiCompareDisplayedCount => "displayed-count"
    UiCompareUnrelated => "unrelated"
  }
}

///|
fn UiCompareCounterOperation::action(
  self : UiCompareCounterOperation,
) -> String {
  match self {
    UiCompareDisplayedCount => "displayed"
    UiCompareUnrelated => "unrelated"
    UiCompareInitialMount => abort("initial mount has no click action")
  }
}

///|
fn ui_compare_keyed_list_operation(
  operation : String,
) -> UiCompareKeyedListOperation {
  match operation {
    "prepend" => UiCompareListPrepend
    "remove-first" | "remove_first" => UiCompareListRemoveFirst
    "reverse" => UiCompareListReverse
    _ => abort("unknown UI compare keyed-list operation: \{operation}")
  }
}

///|
fn UiCompareKeyedListOperation::name(
  self : UiCompareKeyedListOperation,
) -> String {
  match self {
    UiCompareListPrepend => "prepend"
    UiCompareListRemoveFirst => "remove-first"
    UiCompareListReverse => "reverse"
  }
}

///|
fn ui_compare_panel_operation(operation : String) -> UiComparePanelOperation {
  match operation {
    "hidden-update" | "hidden_update" => UiCompareHiddenUpdate
    "open" => UiCompareOpen
    "visible-update" | "visible_update" => UiCompareVisibleUpdate
    "close" => UiCompareClose
    _ => abort("unknown UI compare panel operation: \{operation}")
  }
}

///|
fn UiComparePanelOperation::name(self : UiComparePanelOperation) -> String {
  match self {
    UiCompareHiddenUpdate => "hidden-update"
    UiCompareOpen => "open"
    UiCompareVisibleUpdate => "visible-update"
    UiCompareClose => "close"
  }
}

///|
fn UiComparePanelOperation::action(self : UiComparePanelOperation) -> String {
  match self {
    UiCompareHiddenUpdate => "hidden-update"
    UiCompareOpen => "open"
    UiCompareVisibleUpdate => "visible-update"
    UiCompareClose => "close"
  }
}

///|
fn ui_compare_result_json(
  system : String,
  suite : String,
  operation : String,
  n : Int,
  iterations : Int,
  samples : Array[Double],
) -> String {
  let sample_json = samples.map(sample => "\{sample * 1000.0}").join(",")
  (
    $|{"system":"\{system}","suite":"\{suite}","operation":"\{operation}","n":\{n},"iterations":\{iterations},"unit":"us","samples":[\{sample_json}]}
  )
}

///|
fn ui_compare_make_items(n : Int) -> Array[(String, String)] {
  [
    for i in 0..<n => ("item-\{i}", "Item \{i}")
  ]
}

///|
fn ui_compare_make_item_ids(n : Int) -> Array[String] {
  [
    for i in 0..<n => "item-\{i}"
  ]
}

///|
fn ui_compare_label_for_id(id : String) -> String {
  match id {
    "item-new" => "Prepended"
    _ => id
  }
}
