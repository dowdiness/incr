///|
#cfg(target="js")
priv struct UiCompareIncrRowLeafHarness {
  host : DomElement
  root : DomBenchRoot[UiCompareRowLeafOperation]
}

///|
#cfg(target="js")
fn[Msg] ui_compare_row_leaf_row(
  id : String,
  label : String,
  hot : Bool,
  row_text_hot : Bool,
  row_class_hot : Bool,
  hot_leaf_hot : Bool,
) -> Html[Msg] {
  let row_label = if hot && row_text_hot { "\{label} edited" } else { label }
  let row_class = if hot && row_class_hot {
    "locality-row locality-row-hot"
  } else if hot {
    "locality-row locality-row-cold"
  } else {
    "locality-row"
  }
  let leaf_label = if hot && hot_leaf_hot {
    "hot leaf edited"
  } else if hot {
    "hot leaf baseline"
  } else {
    "cold leaf"
  }
  li(attrs=[class_attr(row_class), attr("data-bench-row-id", id)], [
    span(attrs=[class_attr("list-label")], [text(row_label)]),
    span(attrs=[class_attr("leaf-shell")], [
      span(attrs=[class_attr("leaf-inner")], [
        span(attrs=[class_attr("leaf-text")], [text(leaf_label)]),
      ]),
    ]),
  ])
}

///|
#cfg(target="js")
fn[Msg] ui_compare_row_leaf_list(
  items : Array[(String, String)],
  row_text_hot : Bool,
  row_class_hot : Bool,
  hot_leaf_hot : Bool,
) -> Html[Msg] {
  let hot_index = ui_compare_row_leaf_hot_index(items.length())
  let children = items.mapi((idx, pair) => {
    let (id, label) = pair
    (
      id,
      ui_compare_row_leaf_row(
        id,
        label,
        idx == hot_index,
        row_text_hot,
        row_class_hot,
        hot_leaf_hot,
      ),
    )
  })
  keyed_ul(attrs=[class_attr("keyed-list locality-list")], children)
}

///|
#cfg(target="js")
fn ui_compare_incr_row_leaf_program(
  runtime : @incr.Runtime,
  n : Int,
) -> Program[UiCompareRowLeafOperation, Html[UiCompareRowLeafOperation]] {
  let scope = @incr.Scope::new(runtime)
  let baseline = dom_bench_make_items(n)
  let row_text_hot = scope.input_field(
    false,
    label="ui_compare.incr.row_text_hot",
  )
  let row_class_hot = scope.input_field(
    false,
    label="ui_compare.incr.row_class_hot",
  )
  let hot_leaf_hot = scope.input_field(
    false,
    label="ui_compare.incr.hot_leaf_hot",
  )
  let update : (UiCompareRowLeafOperation) -> Cmd[UiCompareRowLeafOperation] = msg => {
    match msg {
      UiCompareRowTextUpdate => row_text_hot.set(!row_text_hot.peek())
      UiCompareRowClassUpdate => row_class_hot.set(!row_class_hot.peek())
      UiCompareHotLeafTextUpdate => hot_leaf_hot.set(!hot_leaf_hot.peek())
    }
    Cmd::none()
  }
  let view : () -> Html[UiCompareRowLeafOperation] raise Failure = () => {
    div(attrs=[class_attr("row-leaf-bench")], [
      button(
        attrs=[attr("data-bench-action", "row-text")],
        events=[on_click(UiCompareRowTextUpdate)],
        "row text",
      ),
      button(
        attrs=[attr("data-bench-action", "row-class")],
        events=[on_click(UiCompareRowClassUpdate)],
        "row class",
      ),
      button(
        attrs=[attr("data-bench-action", "hot-leaf-text")],
        events=[on_click(UiCompareHotLeafTextUpdate)],
        "hot leaf text",
      ),
      ui_compare_row_leaf_list(
        baseline,
        row_text_hot.get(),
        row_class_hot.get(),
        hot_leaf_hot.get(),
      ),
    ])
  }
  Program::Program(
    runtime,
    scope,
    update,
    view,
    label="ui_compare.incr.row_leaf_view",
  )
}

///|
#cfg(target="js")
fn UiCompareIncrRowLeafHarness::UiCompareIncrRowLeafHarness(
  host : DomElement,
  n : Int,
) -> UiCompareIncrRowLeafHarness {
  let runtime = @incr.Runtime()
  let program = ui_compare_incr_row_leaf_program(runtime, n)
  let root = DomBenchRoot(program, host, KeyedDomPatch)
  root.flush()
  { host, root }
}

///|
#cfg(target="js")
fn UiCompareIncrRowLeafHarness::measure_operation(
  self : UiCompareIncrRowLeafHarness,
  operation : UiCompareRowLeafOperation,
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
fn UiCompareIncrRowLeafHarness::dispose(
  self : UiCompareIncrRowLeafHarness,
) -> Unit {
  self.root.program.dispose()
}

///|
#cfg(target="js")
fn ui_compare_incr_run_row_leaf(
  operation : String,
  n : Int,
  iterations : Int,
  sample_count : Int,
) -> String {
  let op = ui_compare_row_leaf_operation(operation)
  let size = dom_bench_positive(n, 64)
  let iteration_count = dom_bench_positive(iterations, 200)
  let samples_len = dom_bench_positive(sample_count, 9)
  let host = dom_bench_create_host()
  let harness = UiCompareIncrRowLeafHarness(host, size)
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
    "row-leaf",
    op.name(),
    size,
    iteration_count,
    samples,
  )
}
