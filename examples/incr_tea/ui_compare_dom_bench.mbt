///|
/// Mounted browser counter comparison support for the adjacent-framework
/// benchmark slice. The root package owns the `incr_tea` half because the
/// renderer and `Html` value types are intentionally package-private.

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
extern "js" fn ui_compare_dom_install_incr_api(
  run : (String, Int, Int) -> String,
) -> Unit =
  #| (run) => {
  #|   const toInt = (value, fallback) => {
  #|     const parsed = Number(value);
  #|     return Number.isFinite(parsed) ? Math.trunc(parsed) : fallback;
  #|   };
  #|   const api = globalThis.__incrTeaUiCompareDomBench ?? {};
  #|   api.runIncrTea = (operation, iterations = 200, samples = 9) => JSON.parse(run(
  #|     String(operation),
  #|     toInt(iterations, 200),
  #|     toInt(samples, 9),
  #|   ));
  #|   api.run = (system, operation, iterations = 200, samples = 9) => {
  #|     const key = String(system);
  #|     if (key === "incr_tea") return api.runIncrTea(operation, iterations, samples);
  #|     if (api.runAdjacent) return api.runAdjacent(key, operation, iterations, samples);
  #|     throw new Error(`adjacent UI compare benchmark API is not installed: ${key}`);
  #|   };
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
priv struct UiCompareIncrCounterHarness {
  host : DomElement
  root : DomBenchRoot[UiCompareCounterMsg]
}

///|
#cfg(target="js")
fn ui_compare_incr_counter_program(
  runtime : @incr.Runtime,
) -> Program[UiCompareCounterMsg, Html[UiCompareCounterMsg]] {
  let scope = @incr.Scope::new(runtime)
  let count = scope.input_field(0, label="ui_compare.incr.count")
  let unrelated = scope.input_field(0, label="ui_compare.incr.unrelated")
  let update : (UiCompareCounterMsg) -> Cmd[UiCompareCounterMsg] = msg => {
    match msg {
      UiCompareIncrement => count.set(count.peek() + 1)
      UiCompareTouchUnrelated => unrelated.set(unrelated.peek() + 1)
    }
    Cmd::none()
  }
  let view : () -> Html[UiCompareCounterMsg] raise Failure = () => {
    div(attrs=[class_attr("counter")], [
      h2(attrs=[attr("data-bench-count", "true")], [
        text("Count: \{count.get()}"),
      ]),
      button(
        attrs=[attr("data-bench-action", "displayed")],
        events=[on_click(UiCompareIncrement)],
        "+",
      ),
      button(
        attrs=[attr("data-bench-action", "unrelated")],
        events=[on_click(UiCompareTouchUnrelated)],
        "touch unrelated",
      ),
    ])
  }
  Program::Program(runtime, scope, update, view, label="ui_compare.incr.view")
}

///|
#cfg(target="js")
fn UiCompareIncrCounterHarness::UiCompareIncrCounterHarness(
  host : DomElement,
) -> UiCompareIncrCounterHarness {
  let runtime = @incr.Runtime()
  let program = ui_compare_incr_counter_program(runtime)
  let root = DomBenchRoot(program, host, KeyedDomPatch)
  root.flush()
  { host, root }
}

///|
#cfg(target="js")
fn UiCompareIncrCounterHarness::measure_operation(
  self : UiCompareIncrCounterHarness,
  operation : UiCompareCounterOperation,
  iterations : Int,
) -> Double {
  let action = operation.action()
  let total = for _ in 0..<iterations; total = 0.0 {
    let started = dom_bench_now_ms()
    ui_compare_dom_click_action(self.host, action)
    self.root.flush()
    let elapsed = dom_bench_now_ms() - started
    continue total + elapsed
  } nobreak {
    total
  }
  total / iterations.to_double()
}

///|
#cfg(target="js")
fn UiCompareIncrCounterHarness::dispose(
  self : UiCompareIncrCounterHarness,
) -> Unit {
  self.root.program.dispose()
}

///|
#cfg(target="js")
fn ui_compare_incr_measure_initial_mount(iterations : Int) -> Double {
  let total = for _ in 0..<iterations; total = 0.0 {
    let host = dom_bench_create_host()
    let started = dom_bench_now_ms()
    let harness = UiCompareIncrCounterHarness(host)
    let elapsed = dom_bench_now_ms() - started
    harness.dispose()
    dom_bench_remove_host(host)
    continue total + elapsed
  } nobreak {
    total
  }
  total / iterations.to_double()
}

///|
#cfg(target="js")
fn ui_compare_incr_measure_updates(
  operation : UiCompareCounterOperation,
  iterations : Int,
) -> Double {
  let host = dom_bench_create_host()
  let harness = UiCompareIncrCounterHarness(host)
  for _ in 0..<5 {
    ignore(harness.measure_operation(operation, 1))
  }
  let elapsed = harness.measure_operation(operation, iterations)
  harness.dispose()
  dom_bench_remove_host(host)
  elapsed
}

///|
#cfg(target="js")
fn ui_compare_counter_result_json(
  system : String,
  operation : UiCompareCounterOperation,
  iterations : Int,
  samples : Array[Double],
) -> String {
  let sample_json = samples.map(sample => "\{sample * 1000.0}").join(",")
  let json =
    $|{"system":"\{system}","operation":"\{operation.name()}","iterations":\{iterations},"unit":"us","samples":[\{sample_json}]}
  json
}

///|
#cfg(target="js")
fn ui_compare_incr_run(
  operation : String,
  iterations : Int,
  sample_count : Int,
) -> String {
  let op = ui_compare_counter_operation(operation)
  let iteration_count = dom_bench_positive(iterations, 200)
  let samples_len = dom_bench_positive(sample_count, 9)
  let samples = match op {
    UiCompareInitialMount => {
      for _ in 0..<5 {
        ignore(ui_compare_incr_measure_initial_mount(1))
      }
      [
        for _ in 0..<samples_len => {
          ui_compare_incr_measure_initial_mount(iteration_count)
        }
      ]
    }
    _ =>
      [
        for _ in 0..<samples_len => {
          ui_compare_incr_measure_updates(op, iteration_count)
        }
      ]
  }
  ui_compare_counter_result_json("incr_tea", op, iteration_count, samples)
}

///|
/// Installs the `incr_tea` side of `window.__incrTeaUiCompareDomBench`.
#cfg(target="js")
pub fn install_ui_compare_dom_bench_api() -> Unit {
  ui_compare_dom_install_incr_api(ui_compare_incr_run)
}
