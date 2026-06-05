///|
#cfg(target="js")
enum DemoMsg {
  CounterIncrement
  CounterDecrement
  CounterTouchUnrelated
  PanelToggle
  PanelMutateDetail
  ParentTick
  ChildTick
} derive(Eq, Debug)

///|
#cfg(target="js")
fn demo_button(msg : DemoMsg, label : String) -> Html[DemoMsg] {
  button(attrs=[class_attr("demo-button")], events=[on_click(msg)], label)
}

///|
#cfg(target="js")
fn counter_program(runtime : @incr.Runtime) -> Program[DemoMsg, Html[DemoMsg]] {
  let scope = @incr.Scope::new(runtime)
  let count = scope.input_field(0, label="demo.counter.count")
  let unrelated = scope.input_field(0, label="demo.counter.unrelated")
  let update : (DemoMsg) -> Cmd[DemoMsg] = msg => {
    match msg {
      CounterIncrement => {
        count.set(count.peek() + 1)
        Cmd::none()
      }
      CounterDecrement => {
        count.set(count.peek() - 1)
        Cmd::none()
      }
      CounterTouchUnrelated => {
        unrelated.set(unrelated.peek() + 1)
        Cmd::none()
      }
      _ => Cmd::none()
    }
  }
  let view : () -> Html[DemoMsg] raise Failure = () => {
    article(attrs=[class_attr("demo-card counter-card")], [
      h2([text("Counter")]),
      p(attrs=[class_attr("metric-line")], [
        span(attrs=[class_attr("metric-label")], [text("count")]),
        span(attrs=[class_attr("metric-value")], [text("\{count.get()}")]),
      ]),
      div(attrs=[class_attr("button-row")], [
        button(
          attrs=[
            class_attr("demo-button"),
            aria_attr("label", "Decrement counter"),
          ],
          events=[on_click(CounterDecrement)],
          "−",
        ),
        button(
          attrs=[
            class_attr("demo-button"),
            aria_attr("label", "Increment counter"),
          ],
          events=[on_click(CounterIncrement)],
          "+",
        ),
        demo_button(CounterTouchUnrelated, "touch unread field"),
      ]),
      p(attrs=[class_attr("demo-note")], [
        text("The third button mutates an InputField the view never reads."),
      ]),
    ])
  }
  Program::Program(runtime, scope, update, view, label="demo.counter.view")
}

///|
#cfg(target="js")
fn panel_program(runtime : @incr.Runtime) -> Program[DemoMsg, Html[DemoMsg]] {
  let scope = @incr.Scope::new(runtime)
  let open = scope.input_field(false, label="demo.panel.open")
  let detail = scope.input_field(0, label="demo.panel.detail")
  let update : (DemoMsg) -> Cmd[DemoMsg] = msg => {
    match msg {
      PanelToggle => {
        open.set(!open.peek())
        Cmd::none()
      }
      PanelMutateDetail => {
        detail.set(detail.peek() + 1)
        Cmd::none()
      }
      _ => Cmd::none()
    }
  }
  let view : () -> Html[DemoMsg] raise Failure = () => {
    let is_open = open.get()
    let detail_block = if is_open {
      div(attrs=[class_attr("panel-detail")], [
        p([text("Open-panel detail reads: \{detail.get()}")]),
        p(attrs=[class_attr("demo-note")], [
          text("While open, the detail field is a dynamic dependency."),
        ]),
      ])
    } else {
      p(attrs=[class_attr("demo-note")], [
        text("Closed: the view does not read the detail field."),
      ])
    }
    article(attrs=[class_attr("demo-card panel-card")], [
      h2([text("Conditional panel")]),
      p([text(if is_open { "state: open" } else { "state: closed" })]),
      div(attrs=[class_attr("button-row")], [
        demo_button(
          PanelToggle,
          if is_open {
            "close panel"
          } else {
            "open panel"
          },
        ),
        demo_button(PanelMutateDetail, "mutate detail"),
      ]),
      detail_block,
    ])
  }
  Program::Program(runtime, scope, update, view, label="demo.panel.view")
}

///|
#cfg(target="js")
fn parent_program(runtime : @incr.Runtime) -> Program[DemoMsg, Html[DemoMsg]] {
  let scope = @incr.Scope::new(runtime)
  let ticks = scope.input_field(0, label="demo.parent.ticks")
  let update : (DemoMsg) -> Cmd[DemoMsg] = msg => {
    match msg {
      ParentTick => {
        ticks.set(ticks.peek() + 1)
        Cmd::none()
      }
      _ => Cmd::none()
    }
  }
  let view : () -> Html[DemoMsg] raise Failure = () => {
    article(attrs=[class_attr("demo-card nested-parent")], [
      h2([text("Nested parent")]),
      p([text("parent patches: \{ticks.get()}")]),
      demo_button(ParentTick, "update parent only"),
    ])
  }
  Program::Program(runtime, scope, update, view, label="demo.parent.view")
}

///|
#cfg(target="js")
fn child_program(runtime : @incr.Runtime) -> Program[DemoMsg, Html[DemoMsg]] {
  let scope = @incr.Scope::new(runtime)
  let ticks = scope.input_field(0, label="demo.child.ticks")
  let update : (DemoMsg) -> Cmd[DemoMsg] = msg => {
    match msg {
      ChildTick => {
        ticks.set(ticks.peek() + 1)
        Cmd::none()
      }
      _ => Cmd::none()
    }
  }
  let view : () -> Html[DemoMsg] raise Failure = () => {
    article(attrs=[class_attr("demo-card nested-child")], [
      h3([text("Child root")]),
      p([text("child patches: \{ticks.get()}")]),
      demo_button(ChildTick, "update child"),
    ])
  }
  Program::Program(runtime, scope, update, view, label="demo.child.view")
}

///|
#cfg(target="js")
fn render_stats(stats : RenderStats) -> String {
  "view recomputes: \{stats.view_recomputes}\npatch attempts: \{stats.patch_attempts}\nskipped patches: \{stats.skipped_patches}\nrAF flushes: \{stats.frame_flushes}"
}

///|
#cfg(target="js")
fn update_stats(host : DomElement, stats : RenderStats) -> Unit {
  dom_set_element_text(host, render_stats(stats))
}

///|
/// Mounts the browser demo into the static hosts under `mount_id`.
#cfg(target="js")
pub fn mount_browser_demo(mount_id : String) -> Unit {
  let host = dom_get_element_by_id(mount_id)
  let stats_host = dom_query_child_by_id(host, "render-stats")
  let runtime = @incr.Runtime()
  let renderer = BrowserRenderer::BrowserRenderer(runtime, after_flush=stats => {
    update_stats(stats_host, stats)
  })
  renderer.mount(
    dom_query_child_by_id(host, "counter-root"),
    counter_program(runtime),
  )
  renderer.mount(
    dom_query_child_by_id(host, "panel-root"),
    panel_program(runtime),
  )
  renderer.mount(
    dom_query_child_by_id(host, "nested-parent-root"),
    parent_program(runtime),
  )
  renderer.mount(
    dom_query_child_by_id(host, "nested-child-root"),
    child_program(runtime),
  )
  update_stats(stats_host, renderer.stats())
}
