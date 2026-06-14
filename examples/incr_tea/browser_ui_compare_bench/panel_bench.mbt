///|
priv enum RabbitaPanelMsg {
  RabbitaPanelHiddenUpdate
  RabbitaPanelOpen
  RabbitaPanelVisibleUpdate
  RabbitaPanelClose
}

///|
priv struct RabbitaPanelModel {
  open : Bool
  detail : Int
}

///|
fn ui_compare_rabbita_panel_view(
  emit : @rabbita.Emit[RabbitaPanelMsg],
  model : RabbitaPanelModel,
) -> @rabbita.Html {
  let body = if model.open {
    [
      @rabbita_html.p(
        attrs=@rabbita_html.Attrs::build().data_set(
          "bench-panel-detail", "true",
        ),
        "Detail: \{model.detail}",
      ),
      @rabbita_html.button(
        attrs=@rabbita_html.Attrs::build().data_set(
          "bench-action", "visible-update",
        ),
        on_click=emit(RabbitaPanelVisibleUpdate),
        "visible update",
      ),
      @rabbita_html.button(
        attrs=@rabbita_html.Attrs::build().data_set("bench-action", "close"),
        on_click=emit(RabbitaPanelClose),
        "close",
      ),
    ]
  } else {
    [
      @rabbita_html.p(
        attrs=@rabbita_html.Attrs::build().data_set(
          "bench-panel-closed", "true",
        ),
        "Closed",
      ),
      @rabbita_html.button(
        attrs=@rabbita_html.Attrs::build().data_set("bench-action", "open"),
        on_click=emit(RabbitaPanelOpen),
        "open",
      ),
    ]
  }
  @rabbita_html.div(
    class="panel-bench",
    [
      @rabbita_html.button(
        attrs=@rabbita_html.Attrs::build().data_set(
          "bench-action", "hidden-update",
        ),
        on_click=emit(RabbitaPanelHiddenUpdate),
        "hidden update",
      ),
      @rabbita_html.h2("Panel"),
      ..body,
    ],
  )
}

///|
priv struct RabbitaPanelHarness {
  host : @js_dom.Element
  app : @rabbita.App
}

///|
fn RabbitaPanelHarness::RabbitaPanelHarness(
  host : @js_dom.Element,
) -> RabbitaPanelHarness {
  let initial : RabbitaPanelModel = { open: false, detail: 0 }
  let cell = @rabbita.simple_cell(
    model=initial,
    update=(msg, model) => {
      match msg {
        RabbitaPanelHiddenUpdate => { ..model, detail: model.detail + 1 }
        RabbitaPanelOpen => { ..model, open: true }
        RabbitaPanelVisibleUpdate => { ..model, detail: model.detail + 1 }
        RabbitaPanelClose => { ..model, open: false }
      }
    },
    view=ui_compare_rabbita_panel_view,
  )
  let app = @rabbita.new(cell)
  app.mount(ui_compare_host_id(host))
  { host, app }
}

///|
fn RabbitaPanelHarness::reset_before(
  self : RabbitaPanelHarness,
  operation : UiComparePanelOperation,
) -> Unit {
  match operation {
    UiCompareVisibleUpdate | UiCompareClose =>
      ignore(ui_compare_try_click_action(self.host, "open"))
    UiCompareHiddenUpdate | UiCompareOpen => ()
  }
}

///|
fn RabbitaPanelHarness::reset_after(
  self : RabbitaPanelHarness,
  operation : UiComparePanelOperation,
) -> Unit {
  match operation {
    UiCompareOpen | UiCompareVisibleUpdate =>
      ignore(ui_compare_try_click_action(self.host, "close"))
    UiCompareClose => ignore(ui_compare_try_click_action(self.host, "open"))
    UiCompareHiddenUpdate => ()
  }
}

///|
fn RabbitaPanelHarness::measure_operation(
  self : RabbitaPanelHarness,
  operation : UiComparePanelOperation,
  iterations : Int,
) -> Double {
  let action = operation.action()
  let total = for _ in 0..<iterations; total = 0.0 {
    self.reset_before(operation)
    let started = ui_compare_now_ms()
    ui_compare_click_action(self.host, action)
    let elapsed = ui_compare_now_ms() - started
    self.reset_after(operation)
    continue total + elapsed
  } nobreak {
    total
  }
  total / iterations.to_double()
}

///|
fn RabbitaPanelHarness::dispose(self : RabbitaPanelHarness) -> Unit {
  ignore(self.app)
}

///|
fn ui_compare_rabbita_measure_panel(
  operation : UiComparePanelOperation,
  iterations : Int,
) -> Double {
  let host = ui_compare_create_host()
  let harness = RabbitaPanelHarness(host)
  for _ in 0..<5 {
    ignore(harness.measure_operation(operation, 1))
  }
  let elapsed = harness.measure_operation(operation, iterations)
  harness.dispose()
  ui_compare_remove_host(host)
  elapsed
}

///|
fn ui_compare_luna_panel_node() -> @luna_dom.DomNode {
  let open = @luna.signal(false)
  let detail = @luna.signal(0)
  @luna_dom.div(class="panel-bench", [
    @luna_dom.button(
      attrs=[("data-bench-action", @luna_dom.AttrString("hidden-update"))],
      on=@luna_dom.events().click(fn(_) { detail.update(n => n + 1) }),
      [@luna_dom.text("hidden update")],
    ),
    @luna_dom.h2([@luna_dom.text("Panel")]),
    @luna_dom.show(fn() { !open.get() }, fn() {
      @luna_dom.fragment([
        @luna_dom.p(
          attrs=[("data-bench-panel-closed", @luna_dom.AttrString("true"))],
          [@luna_dom.text("Closed")],
        ),
        @luna_dom.button(
          attrs=[("data-bench-action", @luna_dom.AttrString("open"))],
          on=@luna_dom.events().click(fn(_) { open.set(true) }),
          [@luna_dom.text("open")],
        ),
      ])
    }),
    @luna_dom.show(fn() { open.get() }, fn() {
      @luna_dom.fragment([
        @luna_dom.p(
          attrs=[("data-bench-panel-detail", @luna_dom.AttrString("true"))],
          [@luna_dom.text_dyn(fn() { "Detail: \{detail.get()}" })],
        ),
        @luna_dom.button(
          attrs=[("data-bench-action", @luna_dom.AttrString("visible-update"))],
          on=@luna_dom.events().click(fn(_) { detail.update(n => n + 1) }),
          [@luna_dom.text("visible update")],
        ),
        @luna_dom.button(
          attrs=[("data-bench-action", @luna_dom.AttrString("close"))],
          on=@luna_dom.events().click(fn(_) { open.set(false) }),
          [@luna_dom.text("close")],
        ),
      ])
    }),
  ])
}

///|
priv struct LunaPanelHarness {
  host : @js_dom.Element
  dispose : () -> Unit
}

///|
fn LunaPanelHarness::LunaPanelHarness(
  host : @js_dom.Element,
) -> LunaPanelHarness {
  let (_, dispose) = @luna.create_root_with_dispose(fn() {
    @luna_dom.render_to(host, ui_compare_luna_panel_node())
  })
  { host, dispose }
}

///|
fn LunaPanelHarness::reset_before(
  self : LunaPanelHarness,
  operation : UiComparePanelOperation,
) -> Unit {
  match operation {
    UiCompareVisibleUpdate | UiCompareClose =>
      ignore(ui_compare_try_click_action(self.host, "open"))
    UiCompareHiddenUpdate | UiCompareOpen => ()
  }
}

///|
fn LunaPanelHarness::reset_after(
  self : LunaPanelHarness,
  operation : UiComparePanelOperation,
) -> Unit {
  match operation {
    UiCompareOpen | UiCompareVisibleUpdate =>
      ignore(ui_compare_try_click_action(self.host, "close"))
    UiCompareClose => ignore(ui_compare_try_click_action(self.host, "open"))
    UiCompareHiddenUpdate => ()
  }
}

///|
fn LunaPanelHarness::measure_operation(
  self : LunaPanelHarness,
  operation : UiComparePanelOperation,
  iterations : Int,
) -> Double {
  let action = operation.action()
  let total = for _ in 0..<iterations; total = 0.0 {
    self.reset_before(operation)
    let started = ui_compare_now_ms()
    ui_compare_click_action(self.host, action)
    let elapsed = ui_compare_now_ms() - started
    self.reset_after(operation)
    continue total + elapsed
  } nobreak {
    total
  }
  total / iterations.to_double()
}

///|
fn LunaPanelHarness::dispose(self : LunaPanelHarness) -> Unit {
  (self.dispose)()
}

///|
fn ui_compare_luna_measure_panel(
  operation : UiComparePanelOperation,
  iterations : Int,
) -> Double {
  let host = ui_compare_create_host()
  let harness = LunaPanelHarness(host)
  for _ in 0..<5 {
    ignore(harness.measure_operation(operation, 1))
  }
  let elapsed = harness.measure_operation(operation, iterations)
  harness.dispose()
  ui_compare_remove_host(host)
  elapsed
}

///|
fn ui_compare_adjacent_run_panel(
  system : String,
  operation : String,
  iterations : Int,
  sample_count : Int,
) -> String {
  let op = ui_compare_panel_operation(operation)
  let iteration_count = ui_compare_positive(iterations, 200)
  let samples_len = ui_compare_positive(sample_count, 9)
  let samples = match system {
    "rabbita" =>
      [
        for _ in 0..<samples_len => {
          ui_compare_rabbita_measure_panel(op, iteration_count)
        }
      ]
    "luna" =>
      [
        for _ in 0..<samples_len => {
          ui_compare_luna_measure_panel(op, iteration_count)
        }
      ]
    _ => abort("unknown UI compare system: \{system}")
  }
  ui_compare_result_json(
    system,
    "panel",
    op.name(),
    0,
    iteration_count,
    samples,
  )
}
