///|
priv enum RabbitaWorkspaceMsg {
  RabbitaWorkspaceSetCollapsed
  RabbitaWorkspaceSetHiddenMounted
  RabbitaWorkspaceSetVisible
  RabbitaWorkspaceEdit
}

///|
priv struct RabbitaWorkspaceModel {
  items : Array[(String, String)]
  mode : UiCompareWorkspaceMode
  revision : Int
}

///|
fn ui_compare_rabbita_workspace_line(
  id : String,
  label : String,
  hot : Bool,
  revision : Int,
) -> @rabbita.Html {
  let text_label = if hot {
    "let selected_\{revision} = \{label}"
  } else {
    "let \{id} = \{label}"
  }
  @rabbita_html.li(
    class="workspace-line",
    attrs=@rabbita_html.Attrs::build().data_set("bench-row-id", id),
    [
      @rabbita_html.span(class="workspace-gutter", id),
      @rabbita_html.span(class="workspace-code", text_label),
    ],
  )
}

///|
fn ui_compare_rabbita_workspace_editor(
  items : Array[(String, String)],
  revision : Int,
) -> @rabbita.Html {
  let hot_index = ui_compare_row_leaf_hot_index(items.length())
  let children : Map[String, @rabbita.Html] = Map(
    items.mapi((idx, pair) => {
      let (id, label) = pair
      (
        id,
        ui_compare_rabbita_workspace_line(id, label, idx == hot_index, revision),
      )
    }),
  )
  @rabbita_html.section(class="workspace-editor", [
    @rabbita_html.h3("Editor"),
    @rabbita_html.ul(class="workspace-lines", children),
  ])
}

///|
fn ui_compare_rabbita_workspace_sidebar(
  items : Array[(String, String)],
  revision : Int,
) -> @rabbita.Html {
  let children = items.mapi((idx, pair) => {
    let (_, label) = pair
    @rabbita_html.li(class="workspace-symbol", [
      @rabbita_html.span(class="workspace-symbol-name", label),
      @rabbita_html.span(class="workspace-symbol-meta", "#\{idx}@\{revision}"),
    ])
  })
  @rabbita_html.aside(class="workspace-sidebar", [
    @rabbita_html.h3("Sidebar"),
    @rabbita_html.ul(class="workspace-symbols", children),
  ])
}

///|
fn ui_compare_rabbita_workspace_inspector(revision : Int) -> @rabbita.Html {
  let reference_count = revision % 17
  @rabbita_html.aside(class="workspace-inspector", [
    @rabbita_html.h3("Inspector"),
    @rabbita_html.p(
      attrs=@rabbita_html.Attrs::build().data_set(
        "bench-workspace-detail", "true",
      ),
      "Selected binding revision \{revision}",
    ),
    @rabbita_html.ul(class="workspace-diagnostics", [
      @rabbita_html.li("type: Int"),
      @rabbita_html.li("references: \{reference_count}"),
      @rabbita_html.li("diagnostics epoch: \{revision}"),
    ]),
  ])
}

///|
fn ui_compare_rabbita_workspace_content(
  model : RabbitaWorkspaceModel,
) -> @rabbita.Html {
  let hidden = model.mode == UiCompareWorkspaceHiddenMounted
  let content_class = if hidden {
    "workspace-content workspace-content-hidden"
  } else {
    "workspace-content workspace-content-visible"
  }
  let aria_hidden = if hidden { "true" } else { "false" }
  @rabbita_html.section(
    class=content_class,
    hidden~,
    attrs=@rabbita_html.Attrs::build()
      .aria_hidden(aria_hidden)
      .data_set("bench-workspace-content", "true"),
    [
      ui_compare_rabbita_workspace_sidebar(model.items, model.revision),
      ui_compare_rabbita_workspace_editor(model.items, model.revision),
      ui_compare_rabbita_workspace_inspector(model.revision),
    ],
  )
}

///|
fn ui_compare_rabbita_workspace_placeholder() -> @rabbita.Html {
  @rabbita_html.section(
    class="workspace-content workspace-content-collapsed",
    attrs=@rabbita_html.Attrs::build().data_set(
      "bench-workspace-collapsed", "true",
    ),
    [
      @rabbita_html.h3("Workspace collapsed"),
      @rabbita_html.p(
        "Editor, sidebar, and inspector subtrees are not rendered.",
      ),
    ],
  )
}

///|
fn ui_compare_rabbita_workspace_button(
  emit : @rabbita.Emit[RabbitaWorkspaceMsg],
  action : String,
  msg : RabbitaWorkspaceMsg,
  label : String,
) -> @rabbita.Html {
  @rabbita_html.button(
    attrs=@rabbita_html.Attrs::build().data_set("bench-action", action),
    on_click=emit(msg),
    label,
  )
}

///|
fn ui_compare_rabbita_workspace_view(
  emit : @rabbita.Emit[RabbitaWorkspaceMsg],
  model : RabbitaWorkspaceModel,
) -> @rabbita.Html {
  let body = match model.mode {
    UiCompareWorkspaceCollapsed => ui_compare_rabbita_workspace_placeholder()
    UiCompareWorkspaceHiddenMounted | UiCompareWorkspaceVisible =>
      ui_compare_rabbita_workspace_content(model)
  }
  @rabbita_html.div(class="workspace-bench", [
    @rabbita_html.h2("Workspace island"),
    @rabbita_html.div(class="workspace-controls", [
      ui_compare_rabbita_workspace_button(
        emit,
        "set-collapsed",
        RabbitaWorkspaceSetCollapsed,
        "collapse",
      ),
      ui_compare_rabbita_workspace_button(
        emit,
        "set-hidden-mounted",
        RabbitaWorkspaceSetHiddenMounted,
        "hide mounted",
      ),
      ui_compare_rabbita_workspace_button(
        emit,
        "set-visible",
        RabbitaWorkspaceSetVisible,
        "show",
      ),
      ui_compare_rabbita_workspace_button(
        emit,
        "collapsed-update",
        RabbitaWorkspaceEdit,
        "collapsed edit",
      ),
      ui_compare_rabbita_workspace_button(
        emit,
        "hidden-mounted-update",
        RabbitaWorkspaceEdit,
        "hidden mounted edit",
      ),
      ui_compare_rabbita_workspace_button(
        emit,
        "visible-update",
        RabbitaWorkspaceEdit,
        "visible edit",
      ),
    ]),
    body,
  ])
}

///|
priv struct RabbitaWorkspaceHarness {
  host : @js_dom.Element
  app : @rabbita.App
}

///|
fn RabbitaWorkspaceHarness::RabbitaWorkspaceHarness(
  host : @js_dom.Element,
  n : Int,
) -> RabbitaWorkspaceHarness {
  let initial : RabbitaWorkspaceModel = {
    items: ui_compare_make_items(n),
    mode: UiCompareWorkspaceCollapsed,
    revision: 0,
  }
  let cell = @rabbita.simple_cell(
    model=initial,
    update=(msg, model) => {
      match msg {
        RabbitaWorkspaceSetCollapsed =>
          { ..model, mode: UiCompareWorkspaceCollapsed }
        RabbitaWorkspaceSetHiddenMounted =>
          { ..model, mode: UiCompareWorkspaceHiddenMounted }
        RabbitaWorkspaceSetVisible =>
          { ..model, mode: UiCompareWorkspaceVisible }
        RabbitaWorkspaceEdit => { ..model, revision: model.revision + 1 }
      }
    },
    view=ui_compare_rabbita_workspace_view,
  )
  let app = @rabbita.new(cell)
  app.mount(ui_compare_host_id(host))
  { host, app }
}

///|
fn RabbitaWorkspaceHarness::reset_before(
  self : RabbitaWorkspaceHarness,
  operation : UiCompareWorkspaceOperation,
) -> Unit {
  ui_compare_click_action(self.host, operation.mode_action())
}

///|
fn RabbitaWorkspaceHarness::measure_operation(
  self : RabbitaWorkspaceHarness,
  operation : UiCompareWorkspaceOperation,
  iterations : Int,
) -> Double {
  let action = operation.action()
  let total = for _ in 0..<iterations; total = 0.0 {
    self.reset_before(operation)
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
fn RabbitaWorkspaceHarness::dispose(self : RabbitaWorkspaceHarness) -> Unit {
  ignore(self.app)
}

///|
fn ui_compare_rabbita_measure_workspace(
  operation : UiCompareWorkspaceOperation,
  n : Int,
  iterations : Int,
) -> Double {
  let host = ui_compare_create_host()
  let harness = RabbitaWorkspaceHarness(host, n)
  for _ in 0..<5 {
    ignore(harness.measure_operation(operation, 1))
  }
  let elapsed = harness.measure_operation(operation, iterations)
  harness.dispose()
  ui_compare_remove_host(host)
  elapsed
}

///|
fn ui_compare_luna_workspace_line(
  id : String,
  label : String,
  hot : Bool,
  revision : @signals.Signal[Int],
) -> @luna_dom.DomNode {
  let children = if hot {
    [
      @luna_dom.span(class="workspace-gutter", [@luna_dom.text(id)]),
      @luna_dom.span(class="workspace-code", [
        @luna_dom.text_dyn(fn() {
          let rev = revision.get()
          "let selected_\{rev} = \{label}"
        }),
      ]),
    ]
  } else {
    [
      @luna_dom.span(class="workspace-gutter", [@luna_dom.text(id)]),
      @luna_dom.span(class="workspace-code", [
        @luna_dom.text("let \{id} = \{label}"),
      ]),
    ]
  }
  @luna_dom.li(
    class="workspace-line",
    attrs=[("data-bench-row-id", @luna_dom.AttrString(id))],
    children,
  )
}

///|
fn ui_compare_luna_workspace_editor(
  ids : Array[String],
  revision : @signals.Signal[Int],
) -> @luna_dom.DomNode {
  let hot_index = ui_compare_row_leaf_hot_index(ids.length())
  @luna_dom.section(class="workspace-editor", [
    @luna_dom.h3([@luna_dom.text("Editor")]),
    @luna_dom.ul(class="workspace-lines", [
      @luna_dom.for_each(fn() { ids }, fn(id, idx) {
        ui_compare_luna_workspace_line(
          id,
          ui_compare_label_for_id(id),
          idx == hot_index,
          revision,
        )
      }),
    ]),
  ])
}

///|
fn ui_compare_luna_workspace_sidebar(
  ids : Array[String],
  revision : @signals.Signal[Int],
) -> @luna_dom.DomNode {
  @luna_dom.aside(class="workspace-sidebar", [
    @luna_dom.h3([@luna_dom.text("Sidebar")]),
    @luna_dom.ul(class="workspace-symbols", [
      @luna_dom.for_each(fn() { ids }, fn(id, idx) {
        @luna_dom.li(class="workspace-symbol", [
          @luna_dom.span(class="workspace-symbol-name", [
            @luna_dom.text(ui_compare_label_for_id(id)),
          ]),
          @luna_dom.span(class="workspace-symbol-meta", [
            @luna_dom.text_dyn(fn() {
              let rev = revision.get()
              "#\{idx}@\{rev}"
            }),
          ]),
        ])
      }),
    ]),
  ])
}

///|
fn ui_compare_luna_workspace_inspector(
  revision : @signals.Signal[Int],
) -> @luna_dom.DomNode {
  @luna_dom.aside(class="workspace-inspector", [
    @luna_dom.h3([@luna_dom.text("Inspector")]),
    @luna_dom.p(
      attrs=[("data-bench-workspace-detail", @luna_dom.AttrString("true"))],
      [
        @luna_dom.text_dyn(fn() {
          let rev = revision.get()
          "Selected binding revision \{rev}"
        }),
      ],
    ),
    @luna_dom.ul(class="workspace-diagnostics", [
      @luna_dom.li([@luna_dom.text("type: Int")]),
      @luna_dom.li([
        @luna_dom.text_dyn(fn() {
          let rev = revision.get()
          let reference_count = rev % 17
          "references: \{reference_count}"
        }),
      ]),
      @luna_dom.li([
        @luna_dom.text_dyn(fn() {
          let rev = revision.get()
          "diagnostics epoch: \{rev}"
        }),
      ]),
    ]),
  ])
}

///|
fn ui_compare_luna_workspace_content(
  ids : Array[String],
  revision : @signals.Signal[Int],
  hidden : Bool,
) -> @luna_dom.DomNode {
  let content_class = if hidden {
    "workspace-content workspace-content-hidden"
  } else {
    "workspace-content workspace-content-visible"
  }
  let aria_hidden = if hidden { "true" } else { "false" }
  let attrs = if hidden {
    [
      ("aria-hidden", @luna_dom.AttrString(aria_hidden)),
      ("hidden", @luna_dom.AttrString("")),
      ("data-bench-workspace-content", @luna_dom.AttrString("true")),
    ]
  } else {
    [
      ("aria-hidden", @luna_dom.AttrString(aria_hidden)),
      ("data-bench-workspace-content", @luna_dom.AttrString("true")),
    ]
  }
  @luna_dom.section(class=content_class, attrs~, [
    ui_compare_luna_workspace_sidebar(ids, revision),
    ui_compare_luna_workspace_editor(ids, revision),
    ui_compare_luna_workspace_inspector(revision),
  ])
}

///|
fn ui_compare_luna_workspace_node(n : Int) -> @luna_dom.DomNode {
  let ids = ui_compare_make_item_ids(n)
  let mode = @luna.signal(UiCompareWorkspaceCollapsed)
  let revision = @luna.signal(0)
  @luna_dom.div(class="workspace-bench", [
    @luna_dom.h2([@luna_dom.text("Workspace island")]),
    @luna_dom.div(class="workspace-controls", [
      @luna_dom.button(
        attrs=[("data-bench-action", @luna_dom.AttrString("set-collapsed"))],
        on=@luna_dom.events().click(fn(_) {
          mode.set(UiCompareWorkspaceCollapsed)
        }),
        [@luna_dom.text("collapse")],
      ),
      @luna_dom.button(
        attrs=[
          ("data-bench-action", @luna_dom.AttrString("set-hidden-mounted")),
        ],
        on=@luna_dom.events().click(fn(_) {
          mode.set(UiCompareWorkspaceHiddenMounted)
        }),
        [@luna_dom.text("hide mounted")],
      ),
      @luna_dom.button(
        attrs=[("data-bench-action", @luna_dom.AttrString("set-visible"))],
        on=@luna_dom.events().click(fn(_) {
          mode.set(UiCompareWorkspaceVisible)
        }),
        [@luna_dom.text("show")],
      ),
      @luna_dom.button(
        attrs=[("data-bench-action", @luna_dom.AttrString("collapsed-update"))],
        on=@luna_dom.events().click(fn(_) { revision.update(v => v + 1) }),
        [@luna_dom.text("collapsed edit")],
      ),
      @luna_dom.button(
        attrs=[
          ("data-bench-action", @luna_dom.AttrString("hidden-mounted-update")),
        ],
        on=@luna_dom.events().click(fn(_) { revision.update(v => v + 1) }),
        [@luna_dom.text("hidden mounted edit")],
      ),
      @luna_dom.button(
        attrs=[("data-bench-action", @luna_dom.AttrString("visible-update"))],
        on=@luna_dom.events().click(fn(_) { revision.update(v => v + 1) }),
        [@luna_dom.text("visible edit")],
      ),
    ]),
    @luna_dom.show(fn() { mode.get() == UiCompareWorkspaceCollapsed }, fn() {
      @luna_dom.section(
        class="workspace-content workspace-content-collapsed",
        attrs=[("data-bench-workspace-collapsed", @luna_dom.AttrString("true"))],
        [
          @luna_dom.h3([@luna_dom.text("Workspace collapsed")]),
          @luna_dom.p([
            @luna_dom.text(
              "Editor, sidebar, and inspector subtrees are not rendered.",
            ),
          ]),
        ],
      )
    }),
    @luna_dom.show(fn() { mode.get() == UiCompareWorkspaceHiddenMounted }, fn() {
      ui_compare_luna_workspace_content(ids, revision, true)
    }),
    @luna_dom.show(fn() { mode.get() == UiCompareWorkspaceVisible }, fn() {
      ui_compare_luna_workspace_content(ids, revision, false)
    }),
  ])
}

///|
priv struct LunaWorkspaceHarness {
  host : @js_dom.Element
  dispose : () -> Unit
}

///|
fn LunaWorkspaceHarness::LunaWorkspaceHarness(
  host : @js_dom.Element,
  n : Int,
) -> LunaWorkspaceHarness {
  let (_, dispose) = @luna.create_root_with_dispose(fn() {
    @luna_dom.render_to(host, ui_compare_luna_workspace_node(n))
  })
  { host, dispose }
}

///|
fn LunaWorkspaceHarness::reset_before(
  self : LunaWorkspaceHarness,
  operation : UiCompareWorkspaceOperation,
) -> Unit {
  ui_compare_click_action(self.host, operation.mode_action())
}

///|
fn LunaWorkspaceHarness::measure_operation(
  self : LunaWorkspaceHarness,
  operation : UiCompareWorkspaceOperation,
  iterations : Int,
) -> Double {
  let action = operation.action()
  let total = for _ in 0..<iterations; total = 0.0 {
    self.reset_before(operation)
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
fn LunaWorkspaceHarness::dispose(self : LunaWorkspaceHarness) -> Unit {
  (self.dispose)()
}

///|
fn ui_compare_luna_measure_workspace(
  operation : UiCompareWorkspaceOperation,
  n : Int,
  iterations : Int,
) -> Double {
  let host = ui_compare_create_host()
  let harness = LunaWorkspaceHarness(host, n)
  for _ in 0..<5 {
    ignore(harness.measure_operation(operation, 1))
  }
  let elapsed = harness.measure_operation(operation, iterations)
  harness.dispose()
  ui_compare_remove_host(host)
  elapsed
}

///|
fn ui_compare_adjacent_run_workspace(
  system : String,
  operation : String,
  n : Int,
  iterations : Int,
  sample_count : Int,
) -> String {
  let op = ui_compare_workspace_operation(operation)
  let size = ui_compare_positive(n, 256)
  let iteration_count = ui_compare_positive(iterations, 200)
  let samples_len = ui_compare_positive(sample_count, 9)
  let samples = match system {
    "rabbita" =>
      [
        for _ in 0..<samples_len => {
          ui_compare_rabbita_measure_workspace(op, size, iteration_count)
        }
      ]
    "luna" =>
      [
        for _ in 0..<samples_len => {
          ui_compare_luna_measure_workspace(op, size, iteration_count)
        }
      ]
    _ => abort("unknown UI compare system: \{system}")
  }
  ui_compare_result_json(
    system,
    "workspace-island",
    op.name(),
    size,
    iteration_count,
    samples,
  )
}
