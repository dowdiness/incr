///|
priv enum RabbitaRowLeafMsg {
  RabbitaRowTextUpdate
  RabbitaRowClassUpdate
  RabbitaHotLeafTextUpdate
}

///|
priv struct RabbitaRowLeafModel {
  baseline : Array[(String, String)]
  row_text_hot : Bool
  row_class_hot : Bool
  hot_leaf_hot : Bool
}

///|
fn ui_compare_rabbita_locality_row(
  id : String,
  label : String,
  hot : Bool,
  row_text_hot : Bool,
  row_class_hot : Bool,
  hot_leaf_hot : Bool,
) -> @rabbita.Html {
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
  @rabbita_html.li(
    class=row_class,
    attrs=@rabbita_html.Attrs::build().data_set("bench-row-id", id),
    [
      @rabbita_html.span(class="list-label", row_label),
      @rabbita_html.span(class="leaf-shell", [
        @rabbita_html.span(class="leaf-inner", [
          @rabbita_html.span(class="leaf-text", leaf_label),
        ]),
      ]),
    ],
  )
}

///|
fn ui_compare_rabbita_locality_list(
  model : RabbitaRowLeafModel,
) -> @rabbita.Html {
  let hot_index = ui_compare_row_leaf_hot_index(model.baseline.length())
  let children : Map[String, @rabbita.Html] = Map(
    model.baseline.mapi((idx, pair) => {
      let (id, label) = pair
      (
        id,
        ui_compare_rabbita_locality_row(
          id,
          label,
          idx == hot_index,
          model.row_text_hot,
          model.row_class_hot,
          model.hot_leaf_hot,
        ),
      )
    }),
  )
  @rabbita_html.ul(class="keyed-list locality-list", children)
}

///|
fn ui_compare_rabbita_row_leaf_view(
  emit : @rabbita.Emit[RabbitaRowLeafMsg],
  model : RabbitaRowLeafModel,
) -> @rabbita.Html {
  @rabbita_html.div(class="row-leaf-bench", [
    @rabbita_html.button(
      attrs=@rabbita_html.Attrs::build().data_set("bench-action", "row-text"),
      on_click=emit(RabbitaRowTextUpdate),
      "row text",
    ),
    @rabbita_html.button(
      attrs=@rabbita_html.Attrs::build().data_set("bench-action", "row-class"),
      on_click=emit(RabbitaRowClassUpdate),
      "row class",
    ),
    @rabbita_html.button(
      attrs=@rabbita_html.Attrs::build().data_set(
        "bench-action", "hot-leaf-text",
      ),
      on_click=emit(RabbitaHotLeafTextUpdate),
      "hot leaf text",
    ),
    ui_compare_rabbita_locality_list(model),
  ])
}

///|
priv struct RabbitaRowLeafHarness {
  host : @js_dom.Element
  app : @rabbita.App
}

///|
fn RabbitaRowLeafHarness::RabbitaRowLeafHarness(
  host : @js_dom.Element,
  n : Int,
) -> RabbitaRowLeafHarness {
  let baseline = ui_compare_make_items(n)
  let initial : RabbitaRowLeafModel = {
    baseline,
    row_text_hot: false,
    row_class_hot: false,
    hot_leaf_hot: false,
  }
  let cell = @rabbita.simple_cell(
    model=initial,
    update=(msg, model) => {
      match msg {
        RabbitaRowTextUpdate => { ..model, row_text_hot: !model.row_text_hot }
        RabbitaRowClassUpdate =>
          { ..model, row_class_hot: !model.row_class_hot }
        RabbitaHotLeafTextUpdate =>
          { ..model, hot_leaf_hot: !model.hot_leaf_hot }
      }
    },
    view=ui_compare_rabbita_row_leaf_view,
  )
  let app = @rabbita.new(cell)
  app.mount(ui_compare_host_id(host))
  { host, app }
}

///|
fn RabbitaRowLeafHarness::measure_operation(
  self : RabbitaRowLeafHarness,
  operation : UiCompareRowLeafOperation,
  iterations : Int,
) -> Double {
  let action = operation.action()
  let total = for _ in 0..<iterations; total = 0.0 {
    let started = ui_compare_now_ms()
    ui_compare_click_action(self.host, action)
    let elapsed = ui_compare_now_ms() - started
    continue total + elapsed
  } nobreak {
    total
  }
  total / iterations.to_double()
}

///|
fn RabbitaRowLeafHarness::dispose(self : RabbitaRowLeafHarness) -> Unit {
  ignore(self.app)
}

///|
fn ui_compare_rabbita_measure_row_leaf(
  operation : UiCompareRowLeafOperation,
  n : Int,
  iterations : Int,
) -> Double {
  let host = ui_compare_create_host()
  let harness = RabbitaRowLeafHarness(host, n)
  for _ in 0..<5 {
    ignore(harness.measure_operation(operation, 1))
  }
  let elapsed = harness.measure_operation(operation, iterations)
  harness.dispose()
  ui_compare_remove_host(host)
  elapsed
}

///|
fn ui_compare_luna_row_label(
  id : String,
  hot : Bool,
  row_text_hot : @signals.Signal[Bool],
) -> @luna_dom.DomNode {
  let label = ui_compare_label_for_id(id)
  if hot {
    @luna_dom.text_dyn(fn() {
      if row_text_hot.get() {
        "\{label} edited"
      } else {
        label
      }
    })
  } else {
    @luna_dom.text(label)
  }
}

///|
fn ui_compare_luna_row_class(row_class_hot : @signals.Signal[Bool]) -> String {
  if row_class_hot.get() {
    "locality-row locality-row-hot"
  } else {
    "locality-row locality-row-cold"
  }
}

///|
fn ui_compare_luna_leaf_label(
  hot : Bool,
  hot_leaf_hot : @signals.Signal[Bool],
) -> @luna_dom.DomNode {
  if hot {
    @luna_dom.text_dyn(fn() {
      if hot_leaf_hot.get() {
        "hot leaf edited"
      } else {
        "hot leaf baseline"
      }
    })
  } else {
    @luna_dom.text("cold leaf")
  }
}

///|
fn ui_compare_luna_locality_row(
  id : String,
  idx : Int,
  hot_index : Int,
  row_text_hot : @signals.Signal[Bool],
  row_class_hot : @signals.Signal[Bool],
  hot_leaf_hot : @signals.Signal[Bool],
) -> @luna_dom.DomNode {
  let hot = idx == hot_index
  let attrs = [("data-bench-row-id", @luna_dom.AttrString(id))]
  let children = [
    @luna_dom.span(class="list-label", [
      ui_compare_luna_row_label(id, hot, row_text_hot),
    ]),
    @luna_dom.span(class="leaf-shell", [
      @luna_dom.span(class="leaf-inner", [
        @luna_dom.span(class="leaf-text", [
          ui_compare_luna_leaf_label(hot, hot_leaf_hot),
        ]),
      ]),
    ]),
  ]
  if hot {
    @luna_dom.li(
      dyn_class=fn() { ui_compare_luna_row_class(row_class_hot) },
      attrs~,
      children,
    )
  } else {
    @luna_dom.li(class="locality-row", attrs~, children)
  }
}

///|
fn ui_compare_luna_row_leaf_node(n : Int) -> @luna_dom.DomNode {
  let ids = ui_compare_make_item_ids(n)
  let hot_index = ui_compare_row_leaf_hot_index(ids.length())
  let row_text_hot = @luna.signal(false)
  let row_class_hot = @luna.signal(false)
  let hot_leaf_hot = @luna.signal(false)
  @luna_dom.div(class="row-leaf-bench", [
    @luna_dom.button(
      attrs=[("data-bench-action", @luna_dom.AttrString("row-text"))],
      on=@luna_dom.events().click(fn(_) { row_text_hot.update(v => !v) }),
      [@luna_dom.text("row text")],
    ),
    @luna_dom.button(
      attrs=[("data-bench-action", @luna_dom.AttrString("row-class"))],
      on=@luna_dom.events().click(fn(_) { row_class_hot.update(v => !v) }),
      [@luna_dom.text("row class")],
    ),
    @luna_dom.button(
      attrs=[("data-bench-action", @luna_dom.AttrString("hot-leaf-text"))],
      on=@luna_dom.events().click(fn(_) { hot_leaf_hot.update(v => !v) }),
      [@luna_dom.text("hot leaf text")],
    ),
    @luna_dom.ul(class="keyed-list locality-list", [
      @luna_dom.for_each(fn() { ids }, fn(id, idx) {
        ui_compare_luna_locality_row(
          id, idx, hot_index, row_text_hot, row_class_hot, hot_leaf_hot,
        )
      }),
    ]),
  ])
}

///|
priv struct LunaRowLeafHarness {
  host : @js_dom.Element
  dispose : () -> Unit
}

///|
fn LunaRowLeafHarness::LunaRowLeafHarness(
  host : @js_dom.Element,
  n : Int,
) -> LunaRowLeafHarness {
  let (_, dispose) = @luna.create_root_with_dispose(fn() {
    @luna_dom.render_to(host, ui_compare_luna_row_leaf_node(n))
  })
  { host, dispose }
}

///|
fn LunaRowLeafHarness::measure_operation(
  self : LunaRowLeafHarness,
  operation : UiCompareRowLeafOperation,
  iterations : Int,
) -> Double {
  let action = operation.action()
  let total = for _ in 0..<iterations; total = 0.0 {
    let started = ui_compare_now_ms()
    ui_compare_click_action(self.host, action)
    let elapsed = ui_compare_now_ms() - started
    continue total + elapsed
  } nobreak {
    total
  }
  total / iterations.to_double()
}

///|
fn LunaRowLeafHarness::dispose(self : LunaRowLeafHarness) -> Unit {
  (self.dispose)()
}

///|
fn ui_compare_luna_measure_row_leaf(
  operation : UiCompareRowLeafOperation,
  n : Int,
  iterations : Int,
) -> Double {
  let host = ui_compare_create_host()
  let harness = LunaRowLeafHarness(host, n)
  for _ in 0..<5 {
    ignore(harness.measure_operation(operation, 1))
  }
  let elapsed = harness.measure_operation(operation, iterations)
  harness.dispose()
  ui_compare_remove_host(host)
  elapsed
}

///|
fn ui_compare_adjacent_run_row_leaf(
  system : String,
  operation : String,
  n : Int,
  iterations : Int,
  sample_count : Int,
) -> String {
  let op = ui_compare_row_leaf_operation(operation)
  let size = ui_compare_positive(n, 64)
  let iteration_count = ui_compare_positive(iterations, 200)
  let samples_len = ui_compare_positive(sample_count, 9)
  let samples = match system {
    "rabbita" =>
      [
        for _ in 0..<samples_len => {
          ui_compare_rabbita_measure_row_leaf(op, size, iteration_count)
        }
      ]
    "luna" =>
      [
        for _ in 0..<samples_len => {
          ui_compare_luna_measure_row_leaf(op, size, iteration_count)
        }
      ]
    _ => abort("unknown UI compare system: \{system}")
  }
  ui_compare_result_json(
    system,
    "row-leaf",
    op.name(),
    size,
    iteration_count,
    samples,
  )
}
