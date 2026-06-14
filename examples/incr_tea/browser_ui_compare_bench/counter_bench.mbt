///|
priv enum RabbitaCounterMsg {
  RabbitaIncrement
  RabbitaTouchUnrelated
}

///|
priv struct RabbitaCounterModel {
  count : Int
  unrelated : Int
}

///|
fn ui_compare_rabbita_view(
  emit : @rabbita.Emit[RabbitaCounterMsg],
  model : RabbitaCounterModel,
) -> @rabbita.Html {
  @rabbita_html.div(class="counter", [
    @rabbita_html.h2(
      attrs=@rabbita_html.Attrs::build().data_set("bench-count", "true"),
      "Count: \{model.count}",
    ),
    @rabbita_html.button(
      attrs=@rabbita_html.Attrs::build().data_set("bench-action", "displayed"),
      on_click=emit(RabbitaIncrement),
      "+",
    ),
    @rabbita_html.button(
      attrs=@rabbita_html.Attrs::build().data_set("bench-action", "unrelated"),
      on_click=emit(RabbitaTouchUnrelated),
      "touch unrelated",
    ),
  ])
}

///|
priv struct RabbitaCounterHarness {
  host : @js_dom.Element
  app : @rabbita.App
}

///|
fn RabbitaCounterHarness::RabbitaCounterHarness(
  host : @js_dom.Element,
) -> RabbitaCounterHarness {
  let initial : RabbitaCounterModel = { count: 0, unrelated: 0 }
  let cell = @rabbita.simple_cell(
    model=initial,
    update=(msg, model) => {
      match msg {
        RabbitaIncrement => { ..model, count: model.count + 1 }
        RabbitaTouchUnrelated => { ..model, unrelated: model.unrelated + 1 }
      }
    },
    view=ui_compare_rabbita_view,
  )
  let app = @rabbita.new(cell)
  app.mount(ui_compare_host_id(host))
  { host, app }
}

///|
fn RabbitaCounterHarness::measure_operation(
  self : RabbitaCounterHarness,
  operation : UiCompareCounterOperation,
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
fn RabbitaCounterHarness::dispose(self : RabbitaCounterHarness) -> Unit {
  ignore(self.app)
}

///|
fn ui_compare_rabbita_measure_counter_initial_mount(iterations : Int) -> Double {
  let total = for _ in 0..<iterations; total = 0.0 {
    let host = ui_compare_create_host()
    let started = ui_compare_now_ms()
    let harness = RabbitaCounterHarness(host)
    let elapsed = ui_compare_now_ms() - started
    harness.dispose()
    ui_compare_remove_host(host)
    continue total + elapsed
  } nobreak {
    total
  }
  total / iterations.to_double()
}

///|
fn ui_compare_rabbita_measure_counter_updates(
  operation : UiCompareCounterOperation,
  iterations : Int,
) -> Double {
  let host = ui_compare_create_host()
  let harness = RabbitaCounterHarness(host)
  for _ in 0..<5 {
    ignore(harness.measure_operation(operation, 1))
  }
  let elapsed = harness.measure_operation(operation, iterations)
  harness.dispose()
  ui_compare_remove_host(host)
  elapsed
}

///|
fn ui_compare_luna_counter_node() -> @luna_dom.DomNode {
  let count = @luna.signal(0)
  let unrelated = @luna.signal(0)
  @luna_dom.div(class="counter", [
    @luna_dom.h2(attrs=[("data-bench-count", @luna_dom.AttrString("true"))], [
      @luna_dom.text_dyn(fn() { "Count: \{count.get()}" }),
    ]),
    @luna_dom.button(
      attrs=[("data-bench-action", @luna_dom.AttrString("displayed"))],
      on=@luna_dom.events().click(fn(_) { count.update(n => n + 1) }),
      [@luna_dom.text("+")],
    ),
    @luna_dom.button(
      attrs=[("data-bench-action", @luna_dom.AttrString("unrelated"))],
      on=@luna_dom.events().click(fn(_) { unrelated.update(n => n + 1) }),
      [@luna_dom.text("touch unrelated")],
    ),
  ])
}

///|
priv struct LunaCounterHarness {
  host : @js_dom.Element
  dispose : () -> Unit
}

///|
fn LunaCounterHarness::LunaCounterHarness(
  host : @js_dom.Element,
) -> LunaCounterHarness {
  let (_, dispose) = @luna.create_root_with_dispose(fn() {
    @luna_dom.render_to(host, ui_compare_luna_counter_node())
  })
  { host, dispose }
}

///|
fn LunaCounterHarness::measure_operation(
  self : LunaCounterHarness,
  operation : UiCompareCounterOperation,
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
fn LunaCounterHarness::dispose(self : LunaCounterHarness) -> Unit {
  (self.dispose)()
}

///|
fn ui_compare_luna_measure_counter_initial_mount(iterations : Int) -> Double {
  let total = for _ in 0..<iterations; total = 0.0 {
    let host = ui_compare_create_host()
    let started = ui_compare_now_ms()
    let harness = LunaCounterHarness(host)
    let elapsed = ui_compare_now_ms() - started
    harness.dispose()
    ui_compare_remove_host(host)
    continue total + elapsed
  } nobreak {
    total
  }
  total / iterations.to_double()
}

///|
fn ui_compare_luna_measure_counter_updates(
  operation : UiCompareCounterOperation,
  iterations : Int,
) -> Double {
  let host = ui_compare_create_host()
  let harness = LunaCounterHarness(host)
  for _ in 0..<5 {
    ignore(harness.measure_operation(operation, 1))
  }
  let elapsed = harness.measure_operation(operation, iterations)
  harness.dispose()
  ui_compare_remove_host(host)
  elapsed
}

///|
fn ui_compare_counter_samples(
  system : String,
  operation : UiCompareCounterOperation,
  sample_count : Int,
  iterations : Int,
) -> Array[Double] {
  match (system, operation) {
    ("rabbita", UiCompareInitialMount) => {
      for _ in 0..<5 {
        ignore(ui_compare_rabbita_measure_counter_initial_mount(1))
      }
      [
        for _ in 0..<sample_count => {
          ui_compare_rabbita_measure_counter_initial_mount(iterations)
        }
      ]
    }
    ("rabbita", _) =>
      [
        for _ in 0..<sample_count => {
          ui_compare_rabbita_measure_counter_updates(operation, iterations)
        }
      ]
    ("luna", UiCompareInitialMount) => {
      for _ in 0..<5 {
        ignore(ui_compare_luna_measure_counter_initial_mount(1))
      }
      [
        for _ in 0..<sample_count => {
          ui_compare_luna_measure_counter_initial_mount(iterations)
        }
      ]
    }
    ("luna", _) =>
      [
        for _ in 0..<sample_count => {
          ui_compare_luna_measure_counter_updates(operation, iterations)
        }
      ]
    _ => abort("unknown UI compare system: \{system}")
  }
}

///|
fn ui_compare_adjacent_run_counter(
  system : String,
  operation : String,
  iterations : Int,
  sample_count : Int,
) -> String {
  let op = ui_compare_counter_operation(operation)
  let iteration_count = ui_compare_positive(iterations, 200)
  let samples_len = ui_compare_positive(sample_count, 9)
  let samples = ui_compare_counter_samples(
    system, op, samples_len, iteration_count,
  )
  ui_compare_result_json(
    system,
    "counter",
    op.name(),
    0,
    iteration_count,
    samples,
  )
}
