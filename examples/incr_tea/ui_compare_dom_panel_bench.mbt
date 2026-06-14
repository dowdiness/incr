///|
#cfg(target="js")
priv struct UiCompareIncrPanelHarness {
  host : DomElement
  root : DomBenchRoot[UiComparePanelMsg]
}

///|
#cfg(target="js")
fn ui_compare_incr_panel_program(
  runtime : @incr.Runtime,
) -> Program[UiComparePanelMsg, Html[UiComparePanelMsg]] {
  let scope = @incr.Scope::new(runtime)
  let open = scope.input_field(false, label="ui_compare.incr.panel_open")
  let detail = scope.input_field(0, label="ui_compare.incr.panel_detail")
  let update : (UiComparePanelMsg) -> Cmd[UiComparePanelMsg] = msg => {
    match msg {
      UiComparePanelHiddenUpdate => detail.set(detail.peek() + 1)
      UiComparePanelOpen => open.set(true)
      UiComparePanelVisibleUpdate => detail.set(detail.peek() + 1)
      UiComparePanelClose => open.set(false)
    }
    Cmd::none()
  }
  let view : () -> Html[UiComparePanelMsg] raise Failure = () => {
    let body = if open.get() {
      [
        p(attrs=[attr("data-bench-panel-detail", "true")], [
          text("Detail: \{detail.get()}"),
        ]),
        button(
          attrs=[attr("data-bench-action", "visible-update")],
          events=[on_click(UiComparePanelVisibleUpdate)],
          "visible update",
        ),
        button(
          attrs=[attr("data-bench-action", "close")],
          events=[on_click(UiComparePanelClose)],
          "close",
        ),
      ]
    } else {
      [
        p(attrs=[attr("data-bench-panel-closed", "true")], [text("Closed")]),
        button(
          attrs=[attr("data-bench-action", "open")],
          events=[on_click(UiComparePanelOpen)],
          "open",
        ),
      ]
    }
    div(
      attrs=[class_attr("panel-bench")],
      [
        button(
          attrs=[attr("data-bench-action", "hidden-update")],
          events=[on_click(UiComparePanelHiddenUpdate)],
          "hidden update",
        ),
        h2([text("Panel")]),
        ..body,
      ],
    )
  }
  Program::Program(
    runtime,
    scope,
    update,
    view,
    label="ui_compare.incr.panel_view",
  )
}

///|
#cfg(target="js")
fn UiCompareIncrPanelHarness::UiCompareIncrPanelHarness(
  host : DomElement,
) -> UiCompareIncrPanelHarness {
  let runtime = @incr.Runtime()
  let program = ui_compare_incr_panel_program(runtime)
  let root = DomBenchRoot(program, host, KeyedDomPatch)
  root.flush()
  { host, root }
}

///|
#cfg(target="js")
fn UiCompareIncrPanelHarness::reset_before(
  self : UiCompareIncrPanelHarness,
  operation : UiComparePanelOperation,
) -> Unit {
  match operation {
    UiCompareVisibleUpdate | UiCompareClose =>
      if ui_compare_dom_try_click_action(self.host, "open") {
        self.root.flush()
      }
    UiCompareHiddenUpdate | UiCompareOpen => ()
  }
}

///|
#cfg(target="js")
fn UiCompareIncrPanelHarness::reset_after(
  self : UiCompareIncrPanelHarness,
  operation : UiComparePanelOperation,
) -> Unit {
  match operation {
    UiCompareOpen | UiCompareVisibleUpdate =>
      if ui_compare_dom_try_click_action(self.host, "close") {
        self.root.flush()
      }
    UiCompareClose =>
      if ui_compare_dom_try_click_action(self.host, "open") {
        self.root.flush()
      }
    UiCompareHiddenUpdate => ()
  }
}

///|
#cfg(target="js")
fn UiCompareIncrPanelHarness::measure_operation(
  self : UiCompareIncrPanelHarness,
  operation : UiComparePanelOperation,
  iterations : Int,
) -> Double {
  let action = operation.action()
  let total = for _ in 0..<iterations; total = 0.0 {
    self.reset_before(operation)
    let started = dom_bench_now_ms()
    ui_compare_dom_click_action(self.host, action)
    self.root.flush()
    let elapsed = dom_bench_now_ms() - started
    self.reset_after(operation)
    continue total + elapsed
  } nobreak {
    total
  }
  total / iterations.to_double()
}

///|
#cfg(target="js")
fn UiCompareIncrPanelHarness::dispose(self : UiCompareIncrPanelHarness) -> Unit {
  self.root.program.dispose()
}

///|
#cfg(target="js")
fn ui_compare_incr_run_panel(
  operation : String,
  iterations : Int,
  sample_count : Int,
) -> String {
  let op = ui_compare_panel_operation(operation)
  let iteration_count = dom_bench_positive(iterations, 200)
  let samples_len = dom_bench_positive(sample_count, 9)
  let host = dom_bench_create_host()
  let harness = UiCompareIncrPanelHarness(host)
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
    "panel",
    op.name(),
    0,
    iteration_count,
    samples,
  )
}
