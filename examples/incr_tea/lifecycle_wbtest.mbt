///|
test "lifecycle internals: dispose releases watch and cells before post-dispose gc" {
  let runtime = @incr.Runtime()
  let app = CounterApp::with_runtime(runtime)
  let count_id = app.count.id()
  let title_id = app.title.id()
  let unrelated_id = app.unrelated.id()

  ignore(app.view_or_abort())
  let count_info = match runtime.cell_info(count_id) {
    Some(info) => info
    None => fail("mounted count field should be registered")
  }
  let title_info = match runtime.cell_info(title_id) {
    Some(info) => info
    None => fail("mounted title field should be registered")
  }
  let unrelated_info = match runtime.cell_info(unrelated_id) {
    Some(info) => info
    None => fail("mounted unrelated field should be registered")
  }
  let view_id = match count_info.subscribers {
    [id] => id
    _ => fail("mounted count field should feed one watched view root")
  }
  guard title_info.subscribers is [title_view_id] && title_view_id == view_id else {
    fail("mounted title field should feed the same watched view root")
  }
  guard unrelated_info.subscribers is [] else {
    fail("unread field should not feed the watched view root")
  }
  inspect(app.program.scope.is_disposed(), content="false")
  inspect(app.program.view_watch.is_disposed(), content="false")
  inspect(runtime.gc_root_count(view_id), content="1")
  guard runtime.cell_info(view_id) is Some(view_info) &&
    view_info.dependencies.length() == 2 else {
    fail("mounted view root should be watched and primed with dependencies")
  }

  app.dispose()
  app.dispose()
  runtime.gc()

  inspect(app.program.scope.is_disposed(), content="true")
  inspect(app.program.view_watch.is_disposed(), content="true")
  inspect(app.count.is_disposed(), content="true")
  inspect(app.title.is_disposed(), content="true")
  inspect(app.unrelated.is_disposed(), content="true")
  inspect(runtime.gc_root_count(view_id), content="0")
  guard runtime.cell_info(view_id) is None else {
    fail("disposed view root should be absent from runtime introspection")
  }
  guard runtime.cell_info(count_id) is None else {
    fail("disposed count field should be absent from runtime introspection")
  }
  guard runtime.cell_info(title_id) is None else {
    fail("disposed title field should be absent from runtime introspection")
  }
  guard runtime.cell_info(unrelated_id) is None else {
    fail("disposed unrelated field should be absent from runtime introspection")
  }
  inspect(app.dispatch(CounterMsg::Increment), content="false")
  debug_inspect(app.view(), content="None")
}
