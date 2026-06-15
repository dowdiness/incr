///|
#cfg(target="js")
enum RendererMsg {
  Increment
  SetUnrelated(Int)
  TogglePanel
  MutatePanelDetail
  ParentOnly
  ChildOnly
  KeyCaptured(String, String, Bool, Bool)
  PointerCaptured(Int, String, Int, Bool)
} derive(Eq, Debug)

///|
#cfg(target="js")
fn renderer_test_button(msg : RendererMsg, label : String) -> Html[RendererMsg] {
  button(events=[on_click(msg)], label)
}

///|
#cfg(target="js")
fn[Msg] install_view_recompute_counter(
  runtime : @incr.Runtime,
  program : Program[Msg, Html[Msg]],
) -> Ref[Int] {
  let view_id = program.view_id()
  let recomputes = Ref(0)
  let _listener_id = try! runtime.add_derived_event_listener(event => {
    match event {
      @incr.DerivedEvent::Completed(completed) =>
        if completed.cell_id == view_id {
          recomputes.val = recomputes.val + 1
        }
      _ => ()
    }
  })
  recomputes
}

///|
#cfg(target="js")
test "#210: renderer instrumentation does not clobber a pre-existing derived-event listener" {
  let runtime = @incr.Runtime()
  // A host integration installs its own derived-event listener BEFORE the
  // renderer mounts.
  let host_completed = Ref(0)
  try! runtime.on_derived_event(event => {
    if event is @incr.DerivedEvent::Completed(_) {
      host_completed.val = host_completed.val + 1
    }
  })
  // Renderer instrumentation registers additively (was singleton pre-#210,
  // which would have replaced the host listener).
  let view_ids : Ref[Array[@incr.CellId]] = Ref([])
  let stats = RenderStats::RenderStats()
  install_render_recompute_counter(runtime, view_ids, stats) |> ignore
  // Drive a recompute and verify the host listener still fires.
  let s = @incr.Input(runtime, 1)
  let m = @incr.Derived(runtime, () => s.get() * 2)
  ignore(m.read_or_abort())
  inspect(host_completed.val, content="1")
}

///|
#cfg(target="js")
test "renderer root: patch attempts only when watched Html changes" {
  let runtime = @incr.Runtime()
  let scope = @incr.Scope::new(runtime)
  let count = scope.input_field(0, label="renderer.patch.count")
  let unrelated = scope.input_field(0, label="renderer.patch.unrelated")
  let update : (RendererMsg) -> Cmd[RendererMsg] = msg => {
    match msg {
      Increment => {
        count.set(count.peek() + 1)
        Cmd::none()
      }
      SetUnrelated(next) => {
        unrelated.set(next)
        Cmd::none()
      }
      _ => Cmd::none()
    }
  }
  let view : () -> Html[RendererMsg] raise Failure = () => {
    div([
      span([text("count=\{count.get()}")]),
      renderer_test_button(Increment, "+"),
    ])
  }
  let program = Program::Program(
    runtime,
    scope,
    update,
    view,
    label="renderer.patch.view",
  )
  let stats = RenderStats::RenderStats()
  let root = WatchedHtmlRoot::WatchedHtmlRoot(program, stats)

  guard root.read_changed() is Some(_) else {
    fail("initial read should patch")
  }
  inspect(stats.patch_attempts, content="1")
  inspect(stats.skipped_patches, content="0")

  inspect(program.dispatch(SetUnrelated(42)), content="true")
  debug_inspect(root.read_changed(), content="None")
  inspect(stats.patch_attempts, content="1")
  inspect(stats.skipped_patches, content="1")

  inspect(program.dispatch(Increment), content="true")
  guard root.read_changed() is Some(_) else {
    fail("changed count should patch")
  }
  inspect(stats.patch_attempts, content="2")
  inspect(stats.skipped_patches, content="1")

  program.dispose()
}

///|
#cfg(target="js")
test "renderer root: closed panel has dynamic dependencies" {
  let runtime = @incr.Runtime()
  let scope = @incr.Scope::new(runtime)
  let open = scope.input_field(false, label="renderer.panel.open")
  let detail = scope.input_field(0, label="renderer.panel.detail")
  let update : (RendererMsg) -> Cmd[RendererMsg] = msg => {
    match msg {
      TogglePanel => {
        open.set(!open.peek())
        Cmd::none()
      }
      MutatePanelDetail => {
        detail.set(detail.peek() + 1)
        Cmd::none()
      }
      _ => Cmd::none()
    }
  }
  let view : () -> Html[RendererMsg] raise Failure = () => {
    if open.get() {
      div([text("open detail=\{detail.get()}")])
    } else {
      div([
        text("closed"),
        renderer_test_button(MutatePanelDetail, "mutate hidden"),
      ])
    }
  }
  let program = Program::Program(
    runtime,
    scope,
    update,
    view,
    label="renderer.panel.view",
  )
  let recomputes = install_view_recompute_counter(runtime, program)

  inspect(program.dispatch(MutatePanelDetail), content="true")
  ignore(program.read_view_or_abort())
  inspect(recomputes.val, content="0")

  inspect(program.dispatch(TogglePanel), content="true")
  ignore(program.read_view_or_abort())
  inspect(recomputes.val, content="1")

  inspect(program.dispatch(MutatePanelDetail), content="true")
  ignore(program.read_view_or_abort())
  inspect(recomputes.val, content="2")

  program.dispose()
}

///|
#cfg(target="js")
test "#251: semantic editor projection and inspector skip distinct slices" {
  let runtime = @incr.Runtime()
  let model = EditorDemoModel(runtime)
  let projection = editor_projection_program(runtime, model)
  let inspector = editor_inspector_program(runtime, model)
  let stats = RenderStats::RenderStats()
  let projection_root = WatchedHtmlRoot::WatchedHtmlRoot(projection, stats)
  let inspector_root = WatchedHtmlRoot::WatchedHtmlRoot(inspector, stats)
  let projection_recomputes = install_view_recompute_counter(
    runtime, projection,
  )
  let inspector_recomputes = install_view_recompute_counter(runtime, inspector)

  guard projection_root.read_changed() is Some(_) else {
    fail("projection initial patch")
  }
  guard inspector_root.read_changed() is Some(_) else {
    fail("inspector initial patch")
  }
  inspect(stats.patch_attempts, content="2")

  inspect(projection.dispatch(EditorBumpDiagnostics), content="true")
  debug_inspect(projection_root.read_changed(), content="None")
  guard inspector_root.read_changed() is Some(_) else {
    fail("diagnostic edit should patch inspector")
  }
  inspect(stats.patch_attempts, content="3")
  inspect(stats.skipped_patches, content="1")
  inspect(projection_recomputes.val, content="0")
  inspect(inspector_recomputes.val, content="1")

  inspect(projection.dispatch(EditorTouchViewport), content="true")
  guard projection_root.read_changed() is Some(_) else {
    fail("viewport edit should patch projection")
  }
  debug_inspect(inspector_root.read_changed(), content="None")
  inspect(stats.patch_attempts, content="4")
  inspect(stats.skipped_patches, content="2")
  inspect(projection_recomputes.val, content="1")
  inspect(inspector_recomputes.val, content="1")

  inspector.dispose()
  projection.dispose()
}

///|
#cfg(target="js")
test "renderer roots: child boundary skips unchanged watched root" {
  let runtime = @incr.Runtime()
  let parent_scope = @incr.Scope::new(runtime)
  let child_scope = @incr.Scope::new(runtime)
  let parent_count = parent_scope.input_field(0, label="renderer.parent.count")
  let child_count = child_scope.input_field(0, label="renderer.child.count")
  let parent_update : (RendererMsg) -> Cmd[RendererMsg] = msg => {
    match msg {
      ParentOnly => {
        parent_count.set(parent_count.peek() + 1)
        Cmd::none()
      }
      _ => Cmd::none()
    }
  }
  let child_update : (RendererMsg) -> Cmd[RendererMsg] = msg => {
    match msg {
      ChildOnly => {
        child_count.set(child_count.peek() + 1)
        Cmd::none()
      }
      _ => Cmd::none()
    }
  }
  let parent_view : () -> Html[RendererMsg] raise Failure = () => {
    div([
      text("parent=\{parent_count.get()}"),
      renderer_test_button(ParentOnly, "parent"),
    ])
  }
  let child_view : () -> Html[RendererMsg] raise Failure = () => {
    div([
      text("child=\{child_count.get()}"),
      renderer_test_button(ChildOnly, "child"),
    ])
  }
  let parent = Program::Program(
    runtime,
    parent_scope,
    parent_update,
    parent_view,
    label="renderer.parent.view",
  )
  let child = Program::Program(
    runtime,
    child_scope,
    child_update,
    child_view,
    label="renderer.child.view",
  )
  let stats = RenderStats::RenderStats()
  let parent_root = WatchedHtmlRoot::WatchedHtmlRoot(parent, stats)
  let child_root = WatchedHtmlRoot::WatchedHtmlRoot(child, stats)

  guard parent_root.read_changed() is Some(_) else {
    fail("parent initial patch")
  }
  guard child_root.read_changed() is Some(_) else {
    fail("child initial patch")
  }
  inspect(stats.patch_attempts, content="2")

  inspect(parent.dispatch(ParentOnly), content="true")
  guard parent_root.read_changed() is Some(_) else {
    fail("parent update should patch")
  }
  debug_inspect(child_root.read_changed(), content="None")
  inspect(stats.patch_attempts, content="3")
  inspect(stats.skipped_patches, content="1")

  inspect(child.dispatch(ChildOnly), content="true")
  guard child_root.read_changed() is Some(_) else {
    fail("child update should patch")
  }
  debug_inspect(parent_root.read_changed(), content="None")
  inspect(stats.patch_attempts, content="4")
  inspect(stats.skipped_patches, content="2")

  parent.dispose()
  child.dispose()
}

///|
/// Test-only fake DOM host. The lifecycle tests below build `BrowserRoot`s with
/// `rendered = None`, so detach/destroy never invoke a `dom_*` method on this
/// value — it is a struct-field placeholder that lets us drive the unmount state
/// machine in Node, where the real `dom_*` FFI (and `document`) are absent.
#cfg(target="js")
extern "js" fn test_fake_host() -> DomElement =
  #| () => ({})

///|
#cfg(target="js")
extern "js" fn test_event_element() -> DomElement =
  #| () => {
  #|   const listeners = new Map();
  #|   return {
  #|     addEventListener(name, listener) {
  #|       listeners.set(name, listener);
  #|     },
  #|     __trigger(name, event) {
  #|       const listener = listeners.get(name);
  #|       if (!listener) throw new Error(`missing listener for ${name}`);
  #|       listener(event);
  #|     },
  #|   };
  #| }

///|
#cfg(target="js")
extern "js" fn test_trigger_keydown(
  element : DomElement,
  key : String,
  code : String,
  repeat : Bool,
) -> Unit =
  #| (element, key, code, repeat) => {
  #|   element.__trigger("keydown", {
  #|     key,
  #|     code,
  #|     altKey: false,
  #|     ctrlKey: true,
  #|     metaKey: false,
  #|     shiftKey: true,
  #|     repeat,
  #|     preventDefault() { this.defaultPrevented = true; },
  #|   });
  #| }

///|
#cfg(target="js")
extern "js" fn test_trigger_pointer_down(
  element : DomElement,
  pointer_id : Int,
  pointer_type : String,
  button : Int,
  buttons : Int,
) -> Unit =
  #| (element, pointerId, pointerType, button, buttons) => {
  #|   element.__trigger("pointerdown", {
  #|     pointerId,
  #|     pointerType,
  #|     clientX: 12.5,
  #|     clientY: 30.25,
  #|     button,
  #|     buttons,
  #|     altKey: false,
  #|     ctrlKey: false,
  #|     metaKey: true,
  #|     shiftKey: false,
  #|     preventDefault() { this.defaultPrevented = true; },
  #|   });
  #| }

///|
#cfg(target="js")
test "#249: typed keyboard and pointer payloads dispatch through Program::dispatch" {
  let runtime = @incr.Runtime()
  let scope = @incr.Scope::new(runtime)
  let key_seen = scope.input_field("", label="renderer.events.key_seen")
  let pointer_seen = scope.input_field("", label="renderer.events.pointer_seen")
  let update : (RendererMsg) -> Cmd[RendererMsg] = msg => {
    match msg {
      KeyCaptured(key, code, repeat, shift_key) =>
        key_seen.set("\{key}/\{code}/repeat=\{repeat}/shift=\{shift_key}")
      PointerCaptured(pointer_id, pointer_type, button, meta_key) =>
        pointer_seen.set(
          "\{pointer_id}/\{pointer_type}/button=\{button}/meta=\{meta_key}",
        )
      _ => ()
    }
    Cmd::none()
  }
  let view : () -> Html[RendererMsg] raise Failure = () => {
    div([text(key_seen.get()), text(pointer_seen.get())])
  }
  let program = Program::Program(
    runtime,
    scope,
    update,
    view,
    label="renderer.events.view",
  )
  let key_id = KeyEventId("editor.keys")
  let pointer_id = PointerEventId("editor.pointer")
  let payload_resolvers = PayloadResolvers::PayloadResolvers(
    resolve_key=(id, payload) => {
      if id == key_id {
        Some(
          KeyCaptured(
            payload.key,
            payload.code,
            payload.repeat,
            payload.shift_key,
          ),
        )
      } else {
        None
      }
    },
    resolve_pointer=(id, payload) => {
      if id == pointer_id {
        Some(
          PointerCaptured(
            payload.pointer_id,
            payload.pointer_type,
            payload.button,
            payload.meta_key,
          ),
        )
      } else {
        None
      }
    },
  )
  let sink : EventSink[RendererMsg] = {
    dispatch: msg => ignore(program.dispatch(msg)),
    payload_resolvers,
    direct_resolvers: DirectPatchResolvers::DirectPatchResolvers(),
  }
  let element = test_event_element()
  attach_events(
    element,
    [
      on_keydown(id=key_id, prevent_default=true),
      on_pointer_down(id=pointer_id),
    ],
    sink,
  )

  test_trigger_keydown(element, "Enter", "Enter", true)
  test_trigger_pointer_down(element, 7, "pen", 2, 3)

  inspect(key_seen.peek(), content="Enter/Enter/repeat=true/shift=true")
  inspect(pointer_seen.peek(), content="7/pen/button=2/meta=true")
  program.dispose()
}

///|
#cfg(target="js")
fn renderer_counter_program(
  runtime : @incr.Runtime,
  label : String,
) -> Program[RendererMsg, Html[RendererMsg]] {
  let scope = @incr.Scope::new(runtime)
  let count = scope.input_field(0, label="\{label}.count")
  let update : (RendererMsg) -> Cmd[RendererMsg] = msg => {
    match msg {
      Increment => {
        count.set(count.peek() + 1)
        Cmd::none()
      }
      _ => Cmd::none()
    }
  }
  let view : () -> Html[RendererMsg] raise Failure = () => {
    div([
      span([text("count=\{count.get()}")]),
      renderer_test_button(Increment, "+"),
    ])
  }
  Program::Program(runtime, scope, update, view, label="\{label}.view")
}

///|
#cfg(target="js")
test "#209: BrowserRenderer::dispose removes the stored view-recompute listener" {
  let runtime = @incr.Runtime()
  // The renderer installs the derived-event (view-recompute) listener at
  // construction; #209 stores its ListenerId so dispose can remove it.
  let renderer : BrowserRenderer[RendererMsg] = BrowserRenderer::BrowserRenderer(
    runtime,
  )
  // Build a program but do NOT mount it (mount needs real DOM). The priming
  // recompute inside Program::Program runs while view_ids is empty, so it is not
  // counted; pushing the view id mimics what mount() registers.
  let program = renderer_counter_program(runtime, "dispose.listener")
  renderer.view_ids.val.push(program.view_id())

  // A tracked recompute is counted by the stored derived-event listener.
  inspect(program.dispatch(Increment), content="true")
  ignore(program.read_view_or_abort())
  inspect(renderer.stats().view_recomputes, content="1")

  // dispose removes the listener. view_ids is intentionally left intact, so this
  // assertion attributes the stop to listener removal, not view_ids clearing.
  renderer.dispose()
  inspect(program.dispatch(Increment), content="true")
  ignore(program.read_view_or_abort())
  inspect(renderer.stats().view_recomputes, content="1")

  // dispose is idempotent.
  renderer.dispose()
  program.dispose()
}

///|
#cfg(target="js")
test "#209: BrowserRenderer::destroy disposes the root's program and drops it from the flush set" {
  let runtime = @incr.Runtime()
  let renderer : BrowserRenderer[RendererMsg] = BrowserRenderer::BrowserRenderer(
    runtime,
  )
  let program = renderer_counter_program(runtime, "destroy.root")
  // Register a root directly (rendered = None) as mount() would, minus the DOM
  // flush that needs a real browser.
  let root = BrowserRoot::BrowserRoot(
    program,
    test_fake_host(),
    renderer.stats(),
  )
  renderer.roots.push(root)
  renderer.view_ids.val.push(program.view_id())

  inspect(program.is_disposed(), content="false")
  renderer.destroy(root)
  // destroy is logical teardown: the program (scope + watch + cells) is disposed
  // and the root leaves both the flush set and the instrumentation filter.
  inspect(program.is_disposed(), content="true")
  inspect(renderer.roots.length(), content="0")
  inspect(renderer.view_ids.val.length(), content="0")
}

///|
#cfg(target="js")
test "#209: BrowserRenderer::detach drops the root from the flush set but keeps its program alive" {
  let runtime = @incr.Runtime()
  let renderer : BrowserRenderer[RendererMsg] = BrowserRenderer::BrowserRenderer(
    runtime,
  )
  let program = renderer_counter_program(runtime, "detach.root")
  let root = BrowserRoot::BrowserRoot(
    program,
    test_fake_host(),
    renderer.stats(),
  )
  renderer.roots.push(root)
  renderer.view_ids.val.push(program.view_id())

  renderer.detach(root)
  // detach is DOM detachment, not teardown: the root is parked (program alive,
  // still owned by the renderer in `detached`), out of the active flush set. Its
  // instrumentation id stays because the renderer still references the program.
  inspect(program.is_disposed(), content="false")
  inspect(renderer.roots.length(), content="0")
  inspect(renderer.detached.length(), content="1")
  inspect(renderer.view_ids.val.length(), content="1")
  program.dispose()
}

///|
#cfg(target="js")
test "#209: destroy reclaims a detached (parked) root's program" {
  let runtime = @incr.Runtime()
  let renderer : BrowserRenderer[RendererMsg] = BrowserRenderer::BrowserRenderer(
    runtime,
  )
  let program = renderer_counter_program(runtime, "destroy.parked")
  let root = BrowserRoot::BrowserRoot(
    program,
    test_fake_host(),
    renderer.stats(),
  )
  renderer.roots.push(root)
  renderer.view_ids.val.push(program.view_id())

  renderer.detach(root)
  inspect(renderer.detached.length(), content="1")
  inspect(program.is_disposed(), content="false")

  // destroy reaches a parked root, not just a mounted one.
  renderer.destroy(root)
  inspect(renderer.detached.length(), content="0")
  inspect(program.is_disposed(), content="true")
  inspect(renderer.view_ids.val.length(), content="0")
}

///|
#cfg(target="js")
test "#209: dispose reclaims detached roots, not just mounted ones" {
  let runtime = @incr.Runtime()
  let renderer : BrowserRenderer[RendererMsg] = BrowserRenderer::BrowserRenderer(
    runtime,
  )
  let program = renderer_counter_program(runtime, "dispose.parked")
  let root = BrowserRoot::BrowserRoot(
    program,
    test_fake_host(),
    renderer.stats(),
  )
  renderer.roots.push(root)
  renderer.detach(root)
  inspect(program.is_disposed(), content="false")

  renderer.dispose()
  // The parked root is owned by the renderer, so dispose disposes it too.
  inspect(program.is_disposed(), content="true")
  inspect(renderer.detached.length(), content="0")
}

///|
#cfg(target="js")
test "#209: BrowserRenderer::dispose destroys every mounted root" {
  let runtime = @incr.Runtime()
  let renderer : BrowserRenderer[RendererMsg] = BrowserRenderer::BrowserRenderer(
    runtime,
  )
  let a = renderer_counter_program(runtime, "dispose.all.a")
  let b = renderer_counter_program(runtime, "dispose.all.b")
  renderer.roots.push(
    BrowserRoot::BrowserRoot(a, test_fake_host(), renderer.stats()),
  )
  renderer.roots.push(
    BrowserRoot::BrowserRoot(b, test_fake_host(), renderer.stats()),
  )

  renderer.dispose()
  inspect(a.is_disposed(), content="true")
  inspect(b.is_disposed(), content="true")
  inspect(renderer.roots.length(), content="0")
}

///|
#cfg(target="js")
test "#209: detach removes only the targeted root, leaving siblings mounted" {
  let runtime = @incr.Runtime()
  let renderer : BrowserRenderer[RendererMsg] = BrowserRenderer::BrowserRenderer(
    runtime,
  )
  let prog_a = renderer_counter_program(runtime, "detach.sibling.a")
  let prog_b = renderer_counter_program(runtime, "detach.sibling.b")
  let root_a = BrowserRoot::BrowserRoot(
    prog_a,
    test_fake_host(),
    renderer.stats(),
  )
  let root_b = BrowserRoot::BrowserRoot(
    prog_b,
    test_fake_host(),
    renderer.stats(),
  )
  renderer.roots.push(root_a)
  renderer.roots.push(root_b)
  renderer.view_ids.val.push(prog_a.view_id())
  renderer.view_ids.val.push(prog_b.view_id())

  // detach acts on the passed root by identity: only root_a is parked; root_b
  // stays mounted, both programs stay alive, and both instrumentation ids remain.
  renderer.detach(root_a)
  inspect(renderer.roots.length(), content="1")
  inspect(renderer.detached.length(), content="1")
  inspect(renderer.view_ids.val.length(), content="2")
  inspect(prog_a.is_disposed(), content="false")
  inspect(prog_b.is_disposed(), content="false")

  prog_a.dispose()
  prog_b.dispose()
}

///|
#cfg(target="js")
test "#209: destroy keeps a shared Program alive while another root still renders it" {
  let runtime = @incr.Runtime()
  let renderer : BrowserRenderer[RendererMsg] = BrowserRenderer::BrowserRenderer(
    runtime,
  )
  // The same Program backs two mounted roots (e.g. mounted into two hosts).
  let program = renderer_counter_program(runtime, "destroy.shared")
  let root_a = BrowserRoot::BrowserRoot(
    program,
    test_fake_host(),
    renderer.stats(),
  )
  let root_b = BrowserRoot::BrowserRoot(
    program,
    test_fake_host(),
    renderer.stats(),
  )
  renderer.roots.push(root_a)
  renderer.roots.push(root_b)
  renderer.view_ids.val.push(program.view_id())

  // Destroying root_a drops it, but root_b still renders the shared Program, so
  // the program must stay alive (its watch/cells still feed root_b).
  renderer.destroy(root_a)
  inspect(renderer.roots.length(), content="1")
  inspect(program.is_disposed(), content="false")

  // Destroying the last root finally disposes the program.
  renderer.destroy(root_b)
  inspect(renderer.roots.length(), content="0")
  inspect(program.is_disposed(), content="true")
  inspect(renderer.view_ids.val.length(), content="0")
}
