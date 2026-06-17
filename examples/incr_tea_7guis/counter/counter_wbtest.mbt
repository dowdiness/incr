///|
test "counter dispatch updates view state" {
  let app = App(@incr.Runtime())
  let initial = app.program.read_view_or_abort()
  ignore(app.program.dispatch(Increment))
  let after_increment = app.program.read_view_or_abort()

  inspect(app._state.val.count, content="1")
  inspect(initial == view_model({ count: 0 }), content="true")
  inspect(after_increment == view_model({ count: 1 }), content="true")
  inspect(initial == after_increment, content="false")
  app.program.dispose()
}
