///|
#cfg(target="js")
priv struct UiCompareIncrWorkspaceHarness {
  host : DomElement
  root : DomBenchRoot[UiCompareWorkspaceMsg]
}

///|
#cfg(target="js")
fn[Msg] ui_compare_workspace_line(
  id : String,
  label : String,
  hot : Bool,
  revision : Int,
) -> Html[Msg] {
  let text_label = if hot {
    "let selected_\{revision} = \{label}"
  } else {
    "let \{id} = \{label}"
  }
  li(attrs=[class_attr("workspace-line"), attr("data-bench-row-id", id)], [
    span(attrs=[class_attr("workspace-gutter")], [text(id)]),
    span(attrs=[class_attr("workspace-code")], [text(text_label)]),
  ])
}

///|
#cfg(target="js")
fn[Msg] ui_compare_workspace_editor(
  items : Array[(String, String)],
  revision : Int,
) -> Html[Msg] {
  let hot_index = ui_compare_row_leaf_hot_index(items.length())
  let children = items.mapi((idx, pair) => {
    let (id, label) = pair
    (id, ui_compare_workspace_line(id, label, idx == hot_index, revision))
  })
  node("section", attrs=[class_attr("workspace-editor")], [
    h3([text("Editor")]),
    keyed_ul(attrs=[class_attr("workspace-lines")], children),
  ])
}

///|
#cfg(target="js")
fn[Msg] ui_compare_workspace_sidebar(
  items : Array[(String, String)],
  revision : Int,
) -> Html[Msg] {
  let children = items.mapi((idx, pair) => {
    let (_, label) = pair
    li(attrs=[class_attr("workspace-symbol")], [
      span(attrs=[class_attr("workspace-symbol-name")], [text(label)]),
      span(attrs=[class_attr("workspace-symbol-meta")], [
        text("#\{idx}@\{revision}"),
      ]),
    ])
  })
  node("aside", attrs=[class_attr("workspace-sidebar")], [
    h3([text("Sidebar")]),
    ul(attrs=[class_attr("workspace-symbols")], children),
  ])
}

///|
#cfg(target="js")
fn[Msg] ui_compare_workspace_inspector(revision : Int) -> Html[Msg] {
  let reference_count = revision % 17
  node("aside", attrs=[class_attr("workspace-inspector")], [
    h3([text("Inspector")]),
    p(attrs=[attr("data-bench-workspace-detail", "true")], [
      text("Selected binding revision \{revision}"),
    ]),
    ul(attrs=[class_attr("workspace-diagnostics")], [
      li([text("type: Int")]),
      li([text("references: \{reference_count}")]),
      li([text("diagnostics epoch: \{revision}")]),
    ]),
  ])
}

///|
#cfg(target="js")
fn[Msg] ui_compare_workspace_content(
  items : Array[(String, String)],
  revision : Int,
  mode : UiCompareWorkspaceMode,
) -> Html[Msg] {
  let hidden = mode == UiCompareWorkspaceHiddenMounted
  let content_class = if hidden {
    "workspace-content workspace-content-hidden"
  } else {
    "workspace-content workspace-content-visible"
  }
  let aria_hidden = if hidden { "true" } else { "false" }
  let content_attrs = if hidden {
    [
      class_attr(content_class),
      aria_attr("hidden", aria_hidden),
      attr("hidden", ""),
      attr("data-bench-workspace-content", "true"),
    ]
  } else {
    [
      class_attr(content_class),
      aria_attr("hidden", aria_hidden),
      attr("data-bench-workspace-content", "true"),
    ]
  }
  node("section", attrs=content_attrs, [
    ui_compare_workspace_sidebar(items, revision),
    ui_compare_workspace_editor(items, revision),
    ui_compare_workspace_inspector(revision),
  ])
}

///|
#cfg(target="js")
fn[Msg] ui_compare_workspace_placeholder() -> Html[Msg] {
  node(
    "section",
    attrs=[
      class_attr("workspace-content workspace-content-collapsed"),
      attr("data-bench-workspace-collapsed", "true"),
    ],
    [
      h3([text("Workspace collapsed")]),
      p([text("Editor, sidebar, and inspector subtrees are not rendered.")]),
    ],
  )
}

///|
#cfg(target="js")
fn ui_compare_workspace_action_button(
  action : String,
  msg : UiCompareWorkspaceMsg,
  label : String,
) -> Html[UiCompareWorkspaceMsg] {
  button(
    attrs=[attr("data-bench-action", action)],
    events=[on_click(msg)],
    label,
  )
}

///|
#cfg(target="js")
fn ui_compare_incr_workspace_program(
  runtime : @incr.Runtime,
  n : Int,
) -> Program[UiCompareWorkspaceMsg, Html[UiCompareWorkspaceMsg]] {
  let scope = @incr.Scope::new(runtime)
  let items = dom_bench_make_items(n)
  let mode = scope.input_field(
    UiCompareWorkspaceCollapsed,
    label="ui_compare.incr.workspace_mode",
  )
  let revision = scope.input_field(
    0,
    label="ui_compare.incr.workspace_revision",
  )
  let update : (UiCompareWorkspaceMsg) -> Cmd[UiCompareWorkspaceMsg] = msg => {
    match msg {
      UiCompareWorkspaceSetCollapsed => mode.set(UiCompareWorkspaceCollapsed)
      UiCompareWorkspaceSetHiddenMounted =>
        mode.set(UiCompareWorkspaceHiddenMounted)
      UiCompareWorkspaceSetVisible => mode.set(UiCompareWorkspaceVisible)
      UiCompareWorkspaceEdit => revision.set(revision.peek() + 1)
    }
    Cmd::none()
  }
  let view : () -> Html[UiCompareWorkspaceMsg] raise Failure = () => {
    let current_mode = mode.get()
    let body = match current_mode {
      UiCompareWorkspaceCollapsed => ui_compare_workspace_placeholder()
      UiCompareWorkspaceHiddenMounted | UiCompareWorkspaceVisible =>
        ui_compare_workspace_content(items, revision.get(), current_mode)
    }
    div(attrs=[class_attr("workspace-bench")], [
      h2([text("Workspace island")]),
      div(attrs=[class_attr("workspace-controls")], [
        ui_compare_workspace_action_button(
          "set-collapsed",
          UiCompareWorkspaceSetCollapsed,
          "collapse",
        ),
        ui_compare_workspace_action_button(
          "set-hidden-mounted",
          UiCompareWorkspaceSetHiddenMounted,
          "hide mounted",
        ),
        ui_compare_workspace_action_button(
          "set-visible",
          UiCompareWorkspaceSetVisible,
          "show",
        ),
        ui_compare_workspace_action_button(
          "collapsed-update",
          UiCompareWorkspaceEdit,
          "collapsed edit",
        ),
        ui_compare_workspace_action_button(
          "hidden-mounted-update",
          UiCompareWorkspaceEdit,
          "hidden mounted edit",
        ),
        ui_compare_workspace_action_button(
          "visible-update",
          UiCompareWorkspaceEdit,
          "visible edit",
        ),
      ]),
      body,
    ])
  }
  Program::Program(
    runtime,
    scope,
    update,
    view,
    label="ui_compare.incr.workspace_view",
  )
}

///|
#cfg(target="js")
fn UiCompareIncrWorkspaceHarness::UiCompareIncrWorkspaceHarness(
  host : DomElement,
  n : Int,
) -> UiCompareIncrWorkspaceHarness {
  let runtime = @incr.Runtime()
  let program = ui_compare_incr_workspace_program(runtime, n)
  let root = DomBenchRoot(program, host, KeyedDomPatch)
  root.flush()
  { host, root }
}

///|
#cfg(target="js")
fn UiCompareIncrWorkspaceHarness::reset_before(
  self : UiCompareIncrWorkspaceHarness,
  operation : UiCompareWorkspaceOperation,
) -> Unit {
  ui_compare_dom_click_action(self.host, operation.mode_action())
  self.root.flush()
}

///|
#cfg(target="js")
fn UiCompareIncrWorkspaceHarness::measure_operation(
  self : UiCompareIncrWorkspaceHarness,
  operation : UiCompareWorkspaceOperation,
  iterations : Int,
) -> Double {
  let action = operation.action()
  let total = for _ in 0..<iterations; total = 0.0 {
    self.reset_before(operation)
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
fn UiCompareIncrWorkspaceHarness::dispose(
  self : UiCompareIncrWorkspaceHarness,
) -> Unit {
  self.root.program.dispose()
}

///|
#cfg(target="js")
fn ui_compare_incr_run_workspace(
  operation : String,
  n : Int,
  iterations : Int,
  sample_count : Int,
) -> String {
  let op = ui_compare_workspace_operation(operation)
  let size = dom_bench_positive(n, 256)
  let iteration_count = dom_bench_positive(iterations, 200)
  let samples_len = dom_bench_positive(sample_count, 9)
  let host = dom_bench_create_host()
  let harness = UiCompareIncrWorkspaceHarness(host, size)
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
    "workspace-island",
    op.name(),
    size,
    iteration_count,
    samples,
  )
}

///|
#cfg(target="js")
priv enum UiCompareInactiveWorkspaceOperation {
  UiCompareInactiveWorkspaceActiveUpdate
  UiCompareInactiveWorkspaceInactiveUpdate
  UiCompareInactiveWorkspaceActivationCatchUp
}

///|
#cfg(target="js")
fn ui_compare_inactive_workspace_operation(
  operation : String,
) -> UiCompareInactiveWorkspaceOperation {
  match operation {
    "active-hidden-mounted-update"
    | "active_hidden_mounted_update"
    | "active-update"
    | "active_update" => UiCompareInactiveWorkspaceActiveUpdate
    "inactive-update" | "inactive_update" =>
      UiCompareInactiveWorkspaceInactiveUpdate
    "activation-catch-up" | "activation_catch_up" | "activate" =>
      UiCompareInactiveWorkspaceActivationCatchUp
    _ => abort("unknown inactive workspace operation: \{operation}")
  }
}

///|
#cfg(target="js")
fn UiCompareInactiveWorkspaceOperation::name(
  self : UiCompareInactiveWorkspaceOperation,
) -> String {
  match self {
    UiCompareInactiveWorkspaceActiveUpdate => "active-hidden-mounted-update"
    UiCompareInactiveWorkspaceInactiveUpdate => "inactive-update"
    UiCompareInactiveWorkspaceActivationCatchUp => "activation-catch-up"
  }
}

///|
#cfg(target="js")
priv struct UiCompareIncrInactiveWorkspaceHarness {
  host : DomElement
  renderer : BrowserRenderer[UiCompareWorkspaceMsg]
  root : BrowserRoot[UiCompareWorkspaceMsg]
}

///|
#cfg(target="js")
fn UiCompareIncrInactiveWorkspaceHarness::UiCompareIncrInactiveWorkspaceHarness(
  host : DomElement,
  n : Int,
) -> UiCompareIncrInactiveWorkspaceHarness {
  let runtime = @incr.Runtime()
  let renderer : BrowserRenderer[UiCompareWorkspaceMsg] = BrowserRenderer::BrowserRenderer(
    runtime,
  )
  // The benchmark page's immediate rAF shim would run and then latch the
  // renderer's scheduled flag; drive the same flush helpers manually instead.
  match renderer.on_change_listener_id {
    Some(id) => {
      runtime.remove_on_change_listener(id)
      renderer.on_change_listener_id = None
    }
    None => ()
  }
  let program = ui_compare_incr_workspace_program(runtime, n)
  let root = renderer.mount(host, program)
  ui_compare_dom_click_action(host, "set-hidden-mounted")
  root.flush()
  { host, renderer, root }
}

///|
#cfg(target="js")
fn UiCompareIncrInactiveWorkspaceHarness::reset_hidden_active(
  self : UiCompareIncrInactiveWorkspaceHarness,
) -> Unit {
  self.renderer.activate(self.root)
  ui_compare_dom_click_action(self.host, "set-hidden-mounted")
  self.root.flush()
}

///|
#cfg(target="js")
fn UiCompareIncrInactiveWorkspaceHarness::measure_operation(
  self : UiCompareIncrInactiveWorkspaceHarness,
  operation : UiCompareInactiveWorkspaceOperation,
  iterations : Int,
) -> Double {
  let total = for _ in 0..<iterations; total = 0.0 {
    self.reset_hidden_active()
    match operation {
      UiCompareInactiveWorkspaceActiveUpdate => ()
      UiCompareInactiveWorkspaceInactiveUpdate =>
        self.renderer.deactivate(self.root)
      UiCompareInactiveWorkspaceActivationCatchUp => {
        self.renderer.deactivate(self.root)
        ui_compare_dom_click_action(self.host, "hidden-mounted-update")
        self.root.flush_if_active()
      }
    }
    let started = dom_bench_now_ms()
    match operation {
      UiCompareInactiveWorkspaceActiveUpdate => {
        ui_compare_dom_click_action(self.host, "hidden-mounted-update")
        self.root.flush()
      }
      UiCompareInactiveWorkspaceInactiveUpdate => {
        ui_compare_dom_click_action(self.host, "hidden-mounted-update")
        self.root.flush_if_active()
      }
      UiCompareInactiveWorkspaceActivationCatchUp =>
        self.renderer.activate(self.root)
    }
    let elapsed = dom_bench_now_ms() - started
    continue total + elapsed
  } nobreak {
    total
  }
  total / iterations.to_double()
}

///|
#cfg(target="js")
fn UiCompareIncrInactiveWorkspaceHarness::dispose(
  self : UiCompareIncrInactiveWorkspaceHarness,
) -> Unit {
  self.renderer.dispose()
}

///|
#cfg(target="js")
fn ui_compare_incr_run_inactive_workspace(
  operation : String,
  n : Int,
  iterations : Int,
  sample_count : Int,
) -> String {
  let op = ui_compare_inactive_workspace_operation(operation)
  let size = dom_bench_positive(n, 256)
  let iteration_count = dom_bench_positive(iterations, 200)
  let samples_len = dom_bench_positive(sample_count, 9)
  let host = dom_bench_create_host()
  let harness = UiCompareIncrInactiveWorkspaceHarness(host, size)
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
    "workspace-inactive-root",
    op.name(),
    size,
    iteration_count,
    samples,
  )
}
