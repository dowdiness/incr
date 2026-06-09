///|
#cfg(target="js")
enum RendererMsg {
  Increment
  SetUnrelated(Int)
  TogglePanel
  MutatePanelDetail
  ParentOnly
  ChildOnly
} derive(Eq, Debug)

///|
#cfg(target="js")
fn renderer_test_button(msg : RendererMsg, label : String) -> Html[RendererMsg] {
  button(events=[on_click(msg)], label)
}

///|
#cfg(target="js")
fn install_view_recompute_counter(
  runtime : @incr.Runtime,
  program : Program[RendererMsg, Html[RendererMsg]],
) -> Ref[Int] {
  let view_id = program.view_id()
  let recomputes = Ref(0)
  try! runtime.on_derived_event(event => {
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
  // detach is DOM detachment, not teardown: the logical component stays alive
  // (re-mountable via mount(host, program)), but it leaves the active flush set
  // so a later rAF will not re-render it.
  inspect(program.is_disposed(), content="false")
  inspect(renderer.roots.length(), content="0")
  inspect(renderer.view_ids.val.length(), content="0")
  program.dispose()
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

  // detach acts on the passed root by identity: only root_a leaves the flush set
  // and the instrumentation filter; root_b stays mounted and both stay alive.
  renderer.detach(root_a)
  inspect(renderer.roots.length(), content="1")
  inspect(renderer.view_ids.val.length(), content="1")
  inspect(prog_a.is_disposed(), content="false")
  inspect(prog_b.is_disposed(), content="false")

  prog_a.dispose()
  prog_b.dispose()
}
