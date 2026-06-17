///|
test "circle drawer tracks history" {
  let app = App(@incr.Runtime())
  ignore(app.program.dispatch(Add(120, 180)))
  inspect(app._state.val.circles.length(), content="1")
  ignore(app.program.dispatch(SetRadius("40")))
  inspect(selected_radius(app._state.val), content="40")
  ignore(app.program.dispatch(Undo))
  inspect(app._state.val.circles.length(), content="1")
  inspect(app._state.val.circles[0].x, content="120")
  inspect(app._state.val.circles[0].y, content="180")
  inspect(app._state.val.circles[0].radius, content="24")
  app.program.dispose()
}
