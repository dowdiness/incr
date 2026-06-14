///|
/// Mounted browser comparison support for the adjacent-framework benchmark
/// matrix. The root package owns the `incr_tea` half because the renderer and
/// `Html` value types are intentionally package-private.

///|
#cfg(target="js")
priv enum UiCompareCounterMsg {
  UiCompareIncrement
  UiCompareTouchUnrelated
} derive(Eq)

///|
#cfg(target="js")
priv enum UiCompareCounterOperation {
  UiCompareInitialMount
  UiCompareDisplayedCount
  UiCompareUnrelated
}

///|
#cfg(target="js")
priv enum UiCompareKeyedListMsg {
  UiCompareListPrepend
  UiCompareListRemoveFirst
  UiCompareListReverse
  UiCompareListReset
} derive(Eq)

///|
#cfg(target="js")
priv enum UiComparePanelMsg {
  UiComparePanelHiddenUpdate
  UiComparePanelOpen
  UiComparePanelVisibleUpdate
  UiComparePanelClose
} derive(Eq)

///|
#cfg(target="js")
priv enum UiComparePanelOperation {
  UiCompareHiddenUpdate
  UiCompareOpen
  UiCompareVisibleUpdate
  UiCompareClose
}

///|
#cfg(target="js")
priv enum UiCompareRowLeafOperation {
  UiCompareRowTextUpdate
  UiCompareRowClassUpdate
  UiCompareHotLeafTextUpdate
} derive(Eq)

///|
#cfg(target="js")
extern "js" fn ui_compare_dom_click_action(
  host : DomElement,
  action : String,
) -> Unit =
  #| (host, action) => {
  #|   const selector = `[data-bench-action="${CSS.escape(action)}"]`;
  #|   const button = host.querySelector(selector);
  #|   if (!button) throw new Error(`missing benchmark action ${action}`);
  #|   button.click();
  #| }

///|
#cfg(target="js")
extern "js" fn ui_compare_dom_try_click_action(
  host : DomElement,
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
#cfg(target="js")
extern "js" fn ui_compare_dom_install_incr_api(
  run : (String, String, Int, Int, Int) -> String,
) -> Unit =
  #| (run) => {
  #|   const toInt = (value, fallback) => {
  #|     const parsed = Number(value);
  #|     return Number.isFinite(parsed) ? Math.trunc(parsed) : fallback;
  #|   };
  #|   const api = globalThis.__incrTeaUiCompareDomBench ?? {};
  #|   api.runIncrTeaCell = (suite, operation, n = 0, iterations = 200, samples = 9) => JSON.parse(run(
  #|     String(suite),
  #|     String(operation),
  #|     toInt(n, 0),
  #|     toInt(iterations, 200),
  #|     toInt(samples, 9),
  #|   ));
  #|   api.runIncrTea = (operation, iterations = 200, samples = 9) => api.runIncrTeaCell(
  #|     "counter",
  #|     operation,
  #|     0,
  #|     iterations,
  #|     samples,
  #|   );
  #|   api.runCell = (system, suite, operation, n = 0, iterations = 200, samples = 9) => {
  #|     const key = String(system);
  #|     if (key === "incr_tea") {
  #|       return api.runIncrTeaCell(suite, operation, n, iterations, samples);
  #|     }
  #|     if (api.runAdjacentCell) {
  #|       return api.runAdjacentCell(key, suite, operation, n, iterations, samples);
  #|     }
  #|     throw new Error(`adjacent UI compare benchmark API is not installed: ${key}`);
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
#cfg(target="js")
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
#cfg(target="js")
fn UiCompareCounterOperation::name(self : UiCompareCounterOperation) -> String {
  match self {
    UiCompareInitialMount => "initial-mount"
    UiCompareDisplayedCount => "displayed-count"
    UiCompareUnrelated => "unrelated"
  }
}

///|
#cfg(target="js")
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
#cfg(target="js")
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
#cfg(target="js")
fn ui_compare_row_leaf_operation(
  operation : String,
) -> UiCompareRowLeafOperation {
  match operation {
    "row-text" | "row_text" | "same-order-row-text" | "same_order_row_text" =>
      UiCompareRowTextUpdate
    "row-class"
    | "row_class"
    | "row-attr"
    | "row_attr"
    | "row-attribute"
    | "row_attribute" => UiCompareRowClassUpdate
    "hot-leaf-text" | "hot_leaf_text" | "leaf-text" | "leaf_text" =>
      UiCompareHotLeafTextUpdate
    _ => abort("unknown UI compare row/leaf operation: \{operation}")
  }
}

///|
#cfg(target="js")
fn UiComparePanelOperation::name(self : UiComparePanelOperation) -> String {
  match self {
    UiCompareHiddenUpdate => "hidden-update"
    UiCompareOpen => "open"
    UiCompareVisibleUpdate => "visible-update"
    UiCompareClose => "close"
  }
}

///|
#cfg(target="js")
fn UiComparePanelOperation::action(self : UiComparePanelOperation) -> String {
  match self {
    UiCompareHiddenUpdate => "hidden-update"
    UiCompareOpen => "open"
    UiCompareVisibleUpdate => "visible-update"
    UiCompareClose => "close"
  }
}

///|
#cfg(target="js")
fn UiCompareRowLeafOperation::name(self : UiCompareRowLeafOperation) -> String {
  match self {
    UiCompareRowTextUpdate => "row-text"
    UiCompareRowClassUpdate => "row-class"
    UiCompareHotLeafTextUpdate => "hot-leaf-text"
  }
}

///|
#cfg(target="js")
fn UiCompareRowLeafOperation::action(
  self : UiCompareRowLeafOperation,
) -> String {
  self.name()
}

///|
#cfg(target="js")
fn ui_compare_row_leaf_hot_index(n : Int) -> Int {
  guard n > 0 else { 0 }
  n / 2
}

///|
#cfg(target="js")
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
