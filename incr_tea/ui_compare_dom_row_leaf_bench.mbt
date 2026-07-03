///|
#cfg(target="js")
priv struct UiCompareIncrRowLeafHarness {
  host : DomElement
  root : DomBenchRoot[UiCompareRowLeafOperation]
}

///|
#cfg(target="js")
priv struct UiCompareDirectRowLeafHarness {
  host : DomElement
  root : DirectPatchRoot[UiCompareRowLeafOperation]
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
fn ui_compare_direct_row_text_id() -> DirectTextId {
  DirectTextId("ui_compare.row_leaf.hot_row_text")
}

///|
#cfg(target="js")
fn ui_compare_direct_hot_leaf_id() -> DirectTextId {
  DirectTextId("ui_compare.row_leaf.hot_leaf_text")
}

///|
#cfg(target="js")
fn ui_compare_direct_row_class_id() -> DirectAttrId {
  DirectAttrId("ui_compare.row_leaf.hot_row_class")
}

///|
#cfg(target="js")
fn[Msg] ui_compare_direct_row_leaf_row(
  id : String,
  label : String,
  hot : Bool,
) -> Html[Msg] {
  let row_text = if hot {
    direct_text(id=ui_compare_direct_row_text_id(), label)
  } else {
    text(label)
  }
  let row_class = if hot {
    direct_class_attr(
      id=ui_compare_direct_row_class_id(),
      "locality-row locality-row-cold",
    )
  } else {
    class_attr("locality-row")
  }
  let leaf_text = if hot {
    direct_text(id=ui_compare_direct_hot_leaf_id(), "hot leaf baseline")
  } else {
    text("cold leaf")
  }
  li(attrs=[row_class, attr("data-bench-row-id", id)], [
    span(attrs=[class_attr("list-label")], [row_text]),
    span(attrs=[class_attr("leaf-shell")], [
      span(attrs=[class_attr("leaf-inner")], [
        span(attrs=[class_attr("leaf-text")], [leaf_text]),
      ]),
    ]),
  ])
}

///|
#cfg(target="js")
fn[Msg] ui_compare_direct_row_leaf_list(
  items : Array[(String, String)],
) -> Html[Msg] {
  let hot_index = ui_compare_row_leaf_hot_index(items.length())
  let children = items.mapi((idx, pair) => {
    let (id, label) = pair
    (id, ui_compare_direct_row_leaf_row(id, label, idx == hot_index))
  })
  keyed_ul(attrs=[class_attr("keyed-list locality-list")], children)
}

///|
#cfg(target="js")
priv struct UiCompareDirectRowLeafProgram {
  program : Program[UiCompareRowLeafOperation, Html[UiCompareRowLeafOperation]]
  direct_resolvers : DirectPatchResolvers
}

///|
#cfg(target="js")
fn ui_compare_hot_row_label(items : Array[(String, String)]) -> String {
  guard items.length() > 0 else { "" }
  items[ui_compare_row_leaf_hot_index(items.length())].1
}

///|
#cfg(target="js")
fn ui_compare_direct_row_leaf_program(
  runtime : @incr.Runtime,
  n : Int,
) -> UiCompareDirectRowLeafProgram {
  let scope = @incr.Scope::new(runtime)
  let baseline = dom_bench_make_items(n)
  let hot_label = ui_compare_hot_row_label(baseline)
  let row_text_hot = scope.input_field(
    false,
    label="ui_compare.incr_direct.row_text_hot",
  )
  let row_class_hot = scope.input_field(
    false,
    label="ui_compare.incr_direct.row_class_hot",
  )
  let hot_leaf_hot = scope.input_field(
    false,
    label="ui_compare.incr_direct.hot_leaf_hot",
  )
  let row_text = scope.derived(
    () => if row_text_hot.get() { "\{hot_label} edited" } else { hot_label },
    label="ui_compare.incr_direct.row_text",
  )
  let row_class = scope.derived(
    () => {
      if row_class_hot.get() {
        "locality-row locality-row-hot"
      } else {
        "locality-row locality-row-cold"
      }
    },
    label="ui_compare.incr_direct.row_class",
  )
  let hot_leaf = scope.derived(
    () => {
      if hot_leaf_hot.get() {
        "hot leaf edited"
      } else {
        "hot leaf baseline"
      }
    },
    label="ui_compare.incr_direct.hot_leaf",
  )
  let row_text_watch = scope.add_watch(row_text.watch())
  let row_class_watch = scope.add_watch(row_class.watch())
  let hot_leaf_watch = scope.add_watch(hot_leaf.watch())
  ignore(row_text_watch.read_or_abort())
  ignore(row_class_watch.read_or_abort())
  ignore(hot_leaf_watch.read_or_abort())
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
      ui_compare_direct_row_leaf_list(baseline),
    ])
  }
  let program = Program::Program(
    runtime,
    scope,
    update,
    view,
    label="ui_compare.incr_direct.row_leaf_view",
  )
  let row_text_id = ui_compare_direct_row_text_id()
  let hot_leaf_id = ui_compare_direct_hot_leaf_id()
  let row_class_id = ui_compare_direct_row_class_id()
  let direct_resolvers = DirectPatchResolvers::DirectPatchResolvers(
    resolve_text=id => {
      if id == row_text_id {
        Some(row_text_watch.read_or_abort())
      } else if id == hot_leaf_id {
        Some(hot_leaf_watch.read_or_abort())
      } else {
        None
      }
    },
    resolve_attr=id => {
      if id == row_class_id {
        Some(row_class_watch.read_or_abort())
      } else {
        None
      }
    },
  )
  { program, direct_resolvers }
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
fn UiCompareDirectRowLeafHarness::UiCompareDirectRowLeafHarness(
  host : DomElement,
  n : Int,
) -> UiCompareDirectRowLeafHarness {
  let runtime = @incr.Runtime()
  let direct_program = ui_compare_direct_row_leaf_program(runtime, n)
  let root = DirectPatchRoot::DirectPatchRoot(
    direct_program.program,
    host,
    direct_program.direct_resolvers,
  )
  root.flush()
  { host, root }
}

///|
#cfg(target="js")
fn UiCompareDirectRowLeafHarness::measure_operation(
  self : UiCompareDirectRowLeafHarness,
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
fn UiCompareDirectRowLeafHarness::dispose(
  self : UiCompareDirectRowLeafHarness,
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

///|
#cfg(target="js")
fn ui_compare_incr_run_row_leaf_direct(
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
  let harness = UiCompareDirectRowLeafHarness(host, size)
  for _ in 0..<5 {
    ignore(harness.measure_operation(op, 1))
  }
  let samples = [
    for _ in 0..<samples_len => harness.measure_operation(op, iteration_count)
  ]
  harness.dispose()
  dom_bench_remove_host(host)
  ui_compare_result_json(
    "incr_tea-direct",
    "row-leaf",
    op.name(),
    size,
    iteration_count,
    samples,
  )
}
