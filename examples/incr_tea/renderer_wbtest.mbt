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

  parent.dispose()
  child.dispose()
}
