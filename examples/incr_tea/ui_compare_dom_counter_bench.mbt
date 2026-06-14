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
fn ui_compare_incr_measure_counter_initial_mount(iterations : Int) -> Double {
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
fn ui_compare_incr_measure_counter_updates(
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
fn ui_compare_incr_run_counter(
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
        ignore(ui_compare_incr_measure_counter_initial_mount(1))
      }
      [
        for _ in 0..<samples_len => {
          ui_compare_incr_measure_counter_initial_mount(iteration_count)
        }
      ]
    }
    _ =>
      [
        for _ in 0..<samples_len => {
          ui_compare_incr_measure_counter_updates(op, iteration_count)
        }
      ]
  }
  ui_compare_result_json(
    "incr_tea",
    "counter",
    op.name(),
    0,
    iteration_count,
    samples,
  )
}
