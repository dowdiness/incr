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
  // #211: text-input payload (carries the DOM input value through dispatch).
  GreetNameInput(String)
  // #211: keyed-list operations (insert / remove / reorder).
  ListPrepend
  ListRemoveFirst
  ListReverse
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
/// #211 text-input payload demo. The `<input>` emits its DOM value through the
/// pure `on_input(tag="greet.name")` descriptor; the renderer reads the value at
/// the browser boundary and the mount-time resolver turns it into
/// `GreetNameInput(value)`, which updates a model field the view echoes back.
#cfg(target="js")
fn greet_program(runtime : @incr.Runtime) -> Program[DemoMsg, Html[DemoMsg]] {
  let scope = @incr.Scope::new(runtime)
  let name = scope.input_field("", label="demo.greet.name")
  let update : (DemoMsg) -> Cmd[DemoMsg] = msg => {
    match msg {
      GreetNameInput(value) => {
        name.set(value)
        Cmd::none()
      }
      _ => Cmd::none()
    }
  }
  let view : () -> Html[DemoMsg] raise Failure = () => {
    let current = name.get()
    let greeting = if current == "" {
      "Type your name above."
    } else {
      "Hello, \{current}!"
    }
    article(attrs=[class_attr("demo-card greet-card")], [
      h2([text("Text input payload")]),
      input(
        attrs=[
          class_attr("demo-input"),
          attr("value", current),
          attr("placeholder", "your name"),
          aria_attr("label", "Your name"),
        ],
        events=[on_input(tag="greet.name")],
      ),
      p(attrs=[class_attr("metric-line")], [text(greeting)]),
      p(attrs=[class_attr("demo-note")], [
        text(
          "The input's value is dispatched as a Msg payload — the Html stores only a pure tag.",
        ),
      ]),
    ])
  }
  Program::Program(runtime, scope, update, view, label="demo.greet.view")
}

///|
/// Resolver for the greet card's text input. Lives at the js mount boundary, not
/// in the cacheable `Html` value: it maps `(tag, value)` to a message.
#cfg(target="js")
fn greet_on_input(tag : String, value : String) -> DemoMsg? {
  match tag {
    "greet.name" => Some(GreetNameInput(value))
    _ => None
  }
}

///|
/// #211 keyed-list demo. Items carry a stable id key, so prepend/remove/reverse
/// reuse each item's DOM node (and its uncontrolled notes `<input>`, whose typed
/// text rides along) instead of re-patching by position.
#cfg(target="js")
fn list_program(runtime : @incr.Runtime) -> Program[DemoMsg, Html[DemoMsg]] {
  let scope = @incr.Scope::new(runtime)
  // (id, label) pairs; the id is the keyed-child key.
  let items = scope.input_field(
    [("item-1", "Alpha"), ("item-2", "Bravo"), ("item-3", "Charlie")],
    label="demo.list.items",
  )
  let next_id = scope.input_field(4, label="demo.list.next_id")
  let update : (DemoMsg) -> Cmd[DemoMsg] = msg => {
    match msg {
      ListPrepend => {
        let id = next_id.peek()
        next_id.set(id + 1)
        items.set([("item-\{id}", "Item \{id}"), ..items.peek()])
        Cmd::none()
      }
      ListRemoveFirst => {
        match items.peek() {
          [_, .. rest] => items.set(rest.to_array())
          [] => ()
        }
        Cmd::none()
      }
      ListReverse => {
        items.set(items.peek().rev())
        Cmd::none()
      }
      _ => Cmd::none()
    }
  }
  let view : () -> Html[DemoMsg] raise Failure = () => {
    let children = items
      .get()
      .map(pair => {
        let (id, label) = pair
        (
          id,
          li(attrs=[class_attr("list-item")], [
            span(attrs=[class_attr("list-label")], [text("\{label} (\{id})")]),
            input(attrs=[
              class_attr("list-note"),
              attr("placeholder", "notes — survive reorder"),
            ]),
          ]),
        )
      })
    article(attrs=[class_attr("demo-card list-card")], [
      h2([text("Keyed list")]),
      p(attrs=[class_attr("demo-note")], [
        text(
          "Type notes into a row, then reverse/prepend/remove — keyed nodes keep each row's notes with its item.",
        ),
      ]),
      div(attrs=[class_attr("button-row")], [
        demo_button(ListPrepend, "prepend"),
        demo_button(ListRemoveFirst, "remove first"),
        demo_button(ListReverse, "reverse"),
      ]),
      keyed_node("ul", attrs=[class_attr("keyed-list")], children),
    ])
  }
  Program::Program(runtime, scope, update, view, label="demo.list.view")
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
/// Attaches `action` to the click event of the `#id` button under `host`.
#cfg(target="js")
fn wire_button(host : DomElement, id : String, action : () -> Unit) -> Unit {
  dom_add_event_listener(
    dom_query_child_by_id(host, id),
    "click",
    false,
    action,
  )
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
  ignore(
    renderer.mount(
      dom_query_child_by_id(host, "counter-root"),
      counter_program(runtime),
    ),
  )
  ignore(
    renderer.mount(
      dom_query_child_by_id(host, "panel-root"),
      panel_program(runtime),
    ),
  )
  ignore(
    renderer.mount(
      dom_query_child_by_id(host, "nested-parent-root"),
      parent_program(runtime),
    ),
  )
  // #211 text-input payload: the resolver maps the input value to a Msg at the
  // mount boundary, keeping the Html view value closure-free.
  ignore(
    renderer.mount(
      dom_query_child_by_id(host, "greet-root"),
      greet_program(runtime),
      on_input=greet_on_input,
    ),
  )
  // #211 keyed list: prepend/remove/reverse preserve per-item DOM identity.
  ignore(
    renderer.mount(
      dom_query_child_by_id(host, "list-root"),
      list_program(runtime),
    ),
  )
  // The nested child drives the #209 unmount lifecycle. The renderer owns the
  // root across its whole life: detach parks it (DOM gone, Program alive),
  // reattach restores it with state preserved, destroy reclaims it (mounted or
  // parked), and dispose tears the whole renderer down including parked roots.
  let child_root : Ref[BrowserRoot[DemoMsg]?] = Ref(
    Some(
      renderer.mount(
        dom_query_child_by_id(host, "nested-child-root"),
        child_program(runtime),
      ),
    ),
  )
  let refresh = () => update_stats(stats_host, renderer.stats())
  wire_button(host, "detach-child", () => {
    match child_root.val {
      Some(root) => renderer.detach(root)
      None => ()
    }
    refresh()
  })
  wire_button(host, "remount-child", () => {
    match child_root.val {
      Some(root) => renderer.reattach(root)
      None => ()
    }
    refresh()
  })
  wire_button(host, "destroy-child", () => {
    match child_root.val {
      Some(root) => {
        renderer.destroy(root)
        child_root.val = None
      }
      None => ()
    }
    refresh()
  })
  wire_button(host, "dispose-renderer", () => {
    renderer.dispose()
    child_root.val = None
    refresh()
  })
  update_stats(stats_host, renderer.stats())
}
