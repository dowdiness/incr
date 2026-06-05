///|
test "lifecycle: mount read and update through watched view" {
  let app = @incr_tea.CounterApp()

  inspect(app.is_disposed(), content="false")
  let initial = app.view_or_abort()
  inspect(initial.count, content="0")
  inspect(initial.title, content="Counter")

  inspect(app.dispatch(@incr_tea.CounterMsg::Increment), content="true")
  let updated = app.view_or_abort()
  inspect(updated.count, content="1")
  inspect(updated.title, content="Counter")
}

///|
test "lifecycle: dispose is idempotent at public boundaries" {
  let app = @incr_tea.CounterApp()

  ignore(
    app.dispatch(
      @incr_tea.CounterMsg::SetBoth(next_count=7, next_title="Mounted"),
    ),
  )
  app.dispose()
  app.dispose()

  inspect(app.is_disposed(), content="true")
  inspect(app.dispatch(@incr_tea.CounterMsg::Increment), content="false")
  debug_inspect(app.view(), content="None")
  debug_inspect(app.count(), content="None")
  debug_inspect(app.title(), content="None")
  debug_inspect(app.unrelated(), content="None")
}

///|
test "lifecycle: post-dispose boundaries stay deterministic after gc" {
  let runtime = @incr.Runtime()
  let app = @incr_tea.CounterApp::with_runtime(runtime)

  app.dispose()
  runtime.gc()

  inspect(app.is_disposed(), content="true")
  inspect(app.dispatch(@incr_tea.CounterMsg::Decrement), content="false")
  debug_inspect(app.view(), content="None")
  debug_inspect(app.count(), content="None")
  debug_inspect(app.title(), content="None")
  debug_inspect(app.unrelated(), content="None")
}

///|
test "lifecycle: gc immediately after mount preserves unread watched view" {
  let runtime = @incr.Runtime()
  let app = @incr_tea.CounterApp::with_runtime(runtime)

  runtime.gc()

  inspect(app.dispatch(@incr_tea.CounterMsg::Increment), content="true")
  let view = app.view_or_abort()
  inspect(view.count, content="1")
  inspect(view.title, content="Counter")
}

///|
test "lifecycle: gc after dispose leaves public boundary closed" {
  let runtime = @incr.Runtime()
  let app = @incr_tea.CounterApp::with_runtime(runtime)

  ignore(app.view_or_abort())
  app.dispose()
  runtime.gc()

  inspect(app.is_disposed(), content="true")
  inspect(app.dispatch(@incr_tea.CounterMsg::Reset), content="false")
  debug_inspect(app.view(), content="None")
}
