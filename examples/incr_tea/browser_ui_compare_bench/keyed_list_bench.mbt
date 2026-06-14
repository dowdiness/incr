///|
priv enum RabbitaListMsg {
  RabbitaListPrepend
  RabbitaListRemoveFirst
  RabbitaListReverse
  RabbitaListReset
}

///|
priv struct RabbitaListModel {
  baseline : Array[(String, String)]
  items : Array[(String, String)]
}

///|
fn ui_compare_rabbita_row(id : String, label : String) -> @rabbita.Html {
  @rabbita_html.li(class="list-item", [
    @rabbita_html.span(class="list-label", "\{label} (\{id})"),
    @rabbita_html.input(
      class="list-note",
      placeholder="notes — survive reorder",
      @rabbita_html.nothing,
    ),
  ])
}

///|
fn ui_compare_rabbita_keyed_list(
  items : Array[(String, String)],
) -> @rabbita.Html {
  let children : Map[String, @rabbita.Html] = Map(
    items.map(pair => {
      let (id, label) = pair
      (id, ui_compare_rabbita_row(id, label))
    }),
  )
  @rabbita_html.ul(class="keyed-list", children)
}

///|
fn ui_compare_rabbita_list_view(
  emit : @rabbita.Emit[RabbitaListMsg],
  model : RabbitaListModel,
) -> @rabbita.Html {
  @rabbita_html.div(class="list-bench", [
    @rabbita_html.button(
      attrs=@rabbita_html.Attrs::build().data_set("bench-action", "prepend"),
      on_click=emit(RabbitaListPrepend),
      "prepend",
    ),
    @rabbita_html.button(
      attrs=@rabbita_html.Attrs::build().data_set(
        "bench-action", "remove-first",
      ),
      on_click=emit(RabbitaListRemoveFirst),
      "remove first",
    ),
    @rabbita_html.button(
      attrs=@rabbita_html.Attrs::build().data_set("bench-action", "reverse"),
      on_click=emit(RabbitaListReverse),
      "reverse",
    ),
    @rabbita_html.button(
      attrs=@rabbita_html.Attrs::build().data_set("bench-action", "reset"),
      on_click=emit(RabbitaListReset),
      "reset",
    ),
    ui_compare_rabbita_keyed_list(model.items),
  ])
}

///|
priv struct RabbitaListHarness {
  host : @js_dom.Element
  app : @rabbita.App
}

///|
fn RabbitaListHarness::RabbitaListHarness(
  host : @js_dom.Element,
  n : Int,
) -> RabbitaListHarness {
  let baseline = ui_compare_make_items(n)
  let initial : RabbitaListModel = { baseline, items: baseline }
  let cell = @rabbita.simple_cell(
    model=initial,
    update=(msg, model) => {
      match msg {
        RabbitaListPrepend =>
          { ..model, items: [("item-new", "Prepended"), ..model.baseline] }
        RabbitaListRemoveFirst =>
          match model.baseline {
            [_, .. rest] => { ..model, items: rest.to_owned() }
            [] => { ..model, items: [] }
          }
        RabbitaListReverse => { ..model, items: model.baseline.rev() }
        RabbitaListReset => { ..model, items: model.baseline }
      }
    },
    view=ui_compare_rabbita_list_view,
  )
  let app = @rabbita.new(cell)
  app.mount(ui_compare_host_id(host))
  { host, app }
}

///|
fn RabbitaListHarness::measure_operation(
  self : RabbitaListHarness,
  operation : UiCompareKeyedListOperation,
  iterations : Int,
) -> Double {
  let action = operation.name()
  let total = for _ in 0..<iterations; total = 0.0 {
    let started = ui_compare_now_ms()
    ui_compare_click_action(self.host, action)
    let elapsed = ui_compare_now_ms() - started
    ui_compare_click_action(self.host, "reset")
    continue total + elapsed
  } nobreak {
    total
  }
  total / iterations.to_double()
}

///|
fn RabbitaListHarness::dispose(self : RabbitaListHarness) -> Unit {
  ignore(self.app)
}

///|
fn ui_compare_rabbita_measure_keyed_list(
  operation : UiCompareKeyedListOperation,
  n : Int,
  iterations : Int,
) -> Double {
  let host = ui_compare_create_host()
  let harness = RabbitaListHarness(host, n)
  for _ in 0..<5 {
    ignore(harness.measure_operation(operation, 1))
  }
  let elapsed = harness.measure_operation(operation, iterations)
  harness.dispose()
  ui_compare_remove_host(host)
  elapsed
}

///|
fn ui_compare_luna_list_node(n : Int) -> @luna_dom.DomNode {
  let baseline = ui_compare_make_item_ids(n)
  let items = @luna.signal(baseline)
  @luna_dom.div(class="list-bench", [
    @luna_dom.button(
      attrs=[("data-bench-action", @luna_dom.AttrString("prepend"))],
      on=@luna_dom.events().click(fn(_) { items.set(["item-new", ..baseline]) }),
      [@luna_dom.text("prepend")],
    ),
    @luna_dom.button(
      attrs=[("data-bench-action", @luna_dom.AttrString("remove-first"))],
      on=@luna_dom.events().click(fn(_) {
        match baseline {
          [_, .. rest] => items.set(rest.to_owned())
          [] => items.set([])
        }
      }),
      [@luna_dom.text("remove first")],
    ),
    @luna_dom.button(
      attrs=[("data-bench-action", @luna_dom.AttrString("reverse"))],
      on=@luna_dom.events().click(fn(_) { items.set(baseline.rev()) }),
      [@luna_dom.text("reverse")],
    ),
    @luna_dom.button(
      attrs=[("data-bench-action", @luna_dom.AttrString("reset"))],
      on=@luna_dom.events().click(fn(_) { items.set(baseline) }),
      [@luna_dom.text("reset")],
    ),
    @luna_dom.ul(class="keyed-list", [
      @luna_dom.for_each(fn() { items.get() }, fn(id, _) {
        @luna_dom.li(class="list-item", [
          @luna_dom.span(class="list-label", [
            @luna_dom.text("\{ui_compare_label_for_id(id)} (\{id})"),
          ]),
          @luna_dom.input(
            class="list-note",
            placeholder="notes — survive reorder",
          ),
        ])
      }),
    ]),
  ])
}

///|
priv struct LunaListHarness {
  host : @js_dom.Element
  dispose : () -> Unit
}

///|
fn LunaListHarness::LunaListHarness(
  host : @js_dom.Element,
  n : Int,
) -> LunaListHarness {
  let (_, dispose) = @luna.create_root_with_dispose(fn() {
    @luna_dom.render_to(host, ui_compare_luna_list_node(n))
  })
  { host, dispose }
}

///|
fn LunaListHarness::measure_operation(
  self : LunaListHarness,
  operation : UiCompareKeyedListOperation,
  iterations : Int,
) -> Double {
  let action = operation.name()
  let total = for _ in 0..<iterations; total = 0.0 {
    let started = ui_compare_now_ms()
    ui_compare_click_action(self.host, action)
    let elapsed = ui_compare_now_ms() - started
    ui_compare_click_action(self.host, "reset")
    continue total + elapsed
  } nobreak {
    total
  }
  total / iterations.to_double()
}

///|
fn LunaListHarness::dispose(self : LunaListHarness) -> Unit {
  (self.dispose)()
}

///|
fn ui_compare_luna_measure_keyed_list(
  operation : UiCompareKeyedListOperation,
  n : Int,
  iterations : Int,
) -> Double {
  let host = ui_compare_create_host()
  let harness = LunaListHarness(host, n)
  for _ in 0..<5 {
    ignore(harness.measure_operation(operation, 1))
  }
  let elapsed = harness.measure_operation(operation, iterations)
  harness.dispose()
  ui_compare_remove_host(host)
  elapsed
}

///|
fn ui_compare_adjacent_run_keyed_list(
  system : String,
  operation : String,
  n : Int,
  iterations : Int,
  sample_count : Int,
) -> String {
  let op = ui_compare_keyed_list_operation(operation)
  let size = ui_compare_positive(n, 64)
  let iteration_count = ui_compare_positive(iterations, 200)
  let samples_len = ui_compare_positive(sample_count, 9)
  let samples = match system {
    "rabbita" =>
      [
        for _ in 0..<samples_len => {
          ui_compare_rabbita_measure_keyed_list(op, size, iteration_count)
        }
      ]
    "luna" =>
      [
        for _ in 0..<samples_len => {
          ui_compare_luna_measure_keyed_list(op, size, iteration_count)
        }
      ]
    _ => abort("unknown UI compare system: \{system}")
  }
  ui_compare_result_json(
    system,
    "keyed-list",
    op.name(),
    size,
    iteration_count,
    samples,
  )
}
