///|
#cfg(target="js")
priv struct UiCompareIncrKeyedListHarness {
  host : DomElement
  root : DomBenchRoot[UiCompareKeyedListMsg]
}

///|
#cfg(target="js")
fn ui_compare_incr_keyed_list_program(
  runtime : @incr.Runtime,
  n : Int,
) -> Program[UiCompareKeyedListMsg, Html[UiCompareKeyedListMsg]] {
  let scope = @incr.Scope::new(runtime)
  let baseline = dom_bench_make_items(n)
  let items = scope.input_field(baseline, label="ui_compare.incr.keyed_items")
  let update : (UiCompareKeyedListMsg) -> Cmd[UiCompareKeyedListMsg] = msg => {
    match msg {
      UiCompareListPrepend => items.set([("item-new", "Prepended"), ..baseline])
      UiCompareListRemoveFirst =>
        match baseline {
          [_, .. rest] => items.set(rest.to_owned())
          [] => items.set([])
        }
      UiCompareListReverse => items.set(baseline.rev())
      UiCompareListReset => items.set(baseline)
    }
    Cmd::none()
  }
  let view : () -> Html[UiCompareKeyedListMsg] raise Failure = () => {
    div(attrs=[class_attr("list-bench")], [
      button(
        attrs=[attr("data-bench-action", "prepend")],
        events=[on_click(UiCompareListPrepend)],
        "prepend",
      ),
      button(
        attrs=[attr("data-bench-action", "remove-first")],
        events=[on_click(UiCompareListRemoveFirst)],
        "remove first",
      ),
      button(
        attrs=[attr("data-bench-action", "reverse")],
        events=[on_click(UiCompareListReverse)],
        "reverse",
      ),
      button(
        attrs=[attr("data-bench-action", "reset")],
        events=[on_click(UiCompareListReset)],
        "reset",
      ),
      dom_bench_keyed_list(items.get()),
    ])
  }
  Program::Program(
    runtime,
    scope,
    update,
    view,
    label="ui_compare.incr.keyed_list_view",
  )
}

///|
#cfg(target="js")
fn UiCompareIncrKeyedListHarness::UiCompareIncrKeyedListHarness(
  host : DomElement,
  n : Int,
) -> UiCompareIncrKeyedListHarness {
  let runtime = @incr.Runtime()
  let program = ui_compare_incr_keyed_list_program(runtime, n)
  let root = DomBenchRoot(program, host, KeyedDomPatch)
  root.flush()
  { host, root }
}

///|
#cfg(target="js")
fn UiCompareIncrKeyedListHarness::measure_operation(
  self : UiCompareIncrKeyedListHarness,
  operation : DomBenchOperation,
  iterations : Int,
) -> Double {
  let action = operation.name()
  let total = for _ in 0..<iterations; total = 0.0 {
    let started = dom_bench_now_ms()
    ui_compare_dom_click_action(self.host, action)
    self.root.flush()
    let elapsed = dom_bench_now_ms() - started
    ui_compare_dom_click_action(self.host, "reset")
    self.root.flush()
    continue total + elapsed
  } nobreak {
    total
  }
  total / iterations.to_double()
}

///|
#cfg(target="js")
fn UiCompareIncrKeyedListHarness::dispose(
  self : UiCompareIncrKeyedListHarness,
) -> Unit {
  self.root.program.dispose()
}

///|
#cfg(target="js")
fn ui_compare_incr_run_keyed_list(
  operation : String,
  n : Int,
  iterations : Int,
  sample_count : Int,
) -> String {
  let op = dom_bench_operation(operation)
  let size = dom_bench_positive(n, 64)
  let iteration_count = dom_bench_positive(iterations, 200)
  let samples_len = dom_bench_positive(sample_count, 9)
  let host = dom_bench_create_host()
  let harness = UiCompareIncrKeyedListHarness(host, size)
  for _ in 0..<5 {
    ignore(harness.measure_operation(op, 1))
  }
  let samples = [
    for _ in 0..<samples_len => harness.measure_operation(op, iteration_count)
  ]
  harness.dispose()
  dom_bench_remove_host(host)
  ui_compare_result_json(
    "incr_tea",
    "keyed-list",
    op.name(),
    size,
    iteration_count,
    samples,
  )
}
