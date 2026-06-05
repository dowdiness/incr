///|
fn install_completed_recompute_counter(runtime : @incr.Runtime) -> Ref[Int] {
  let completed : Ref[Int] = { val: 0 }
  try! runtime.on_derived_event(event => {
    match event {
      @incr.DerivedEvent::Completed(_) => completed.val = completed.val + 1
      _ => ()
    }
  })
  completed
}

///|
test "counter: dispatch batches model update and tracked view update" {
  let runtime = @incr.Runtime()
  let app = @incr_tea.CounterApp::with_runtime(runtime)
  let recomputes = install_completed_recompute_counter(runtime)

  let initial = app.view_or_abort()
  inspect(initial.count, content="0")
  inspect(initial.title, content="Counter")
  inspect(recomputes.val, content="0")

  inspect(app.dispatch(@incr_tea.CounterMsg::Increment), content="true")
  let after_increment = app.view_or_abort()
  inspect(after_increment.count, content="1")
  inspect(after_increment.title, content="Counter")
  inspect(recomputes.val, content="1")
}

///|
test "counter: unread field update does not recompute view" {
  let runtime = @incr.Runtime()
  let app = @incr_tea.CounterApp::with_runtime(runtime)
  let recomputes = install_completed_recompute_counter(runtime)

  inspect(app.dispatch(@incr_tea.CounterMsg::SetUnrelated(7)), content="true")
  debug_inspect(app.unrelated(), content="Some(7)")
  let view = app.view_or_abort()
  inspect(view.count, content="0")
  inspect(view.title, content="Counter")
  inspect(recomputes.val, content="0")
}

///|
test "counter: watched view survives runtime gc while mounted" {
  let app = @incr_tea.CounterApp()

  ignore(app.view_or_abort())
  app.runtime().gc()
  inspect(app.dispatch(@incr_tea.CounterMsg::Increment), content="true")
  let view = app.view_or_abort()
  inspect(view.count, content="1")
}

///|
test "counter: multi-field message commits as one runtime change" {
  let changes : Ref[Int] = { val: 0 }
  let runtime = @incr.Runtime(on_change=() => changes.val = changes.val + 1)
  let app = @incr_tea.CounterApp::with_runtime(runtime)

  inspect(changes.val, content="0")
  inspect(
    app.dispatch(
      @incr_tea.CounterMsg::SetBoth(next_count=5, next_title="Batch"),
    ),
    content="true",
  )
  inspect(changes.val, content="1")
  let view = app.view_or_abort()
  inspect(view.count, content="5")
  inspect(view.title, content="Batch")
}

///|
test "counter: disposed app ignores later messages" {
  let app = @incr_tea.CounterApp()

  app.dispose()
  inspect(app.is_mounted(), content="false")
  inspect(app.dispatch(@incr_tea.CounterMsg::Increment), content="false")
  debug_inspect(app.view(), content="None")
  debug_inspect(app.count(), content="None")
  debug_inspect(app.title(), content="None")
  debug_inspect(app.unrelated(), content="None")
}
