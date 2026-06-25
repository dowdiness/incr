///|
test "keyboard shortcut: pressed increments count and reset clears it" {
  let runtime = @incr.Runtime()
  let app = App(runtime)

  inspect(app._state.val.count, content="0")
  inspect(app._state.val.listening, content="true")
  ignore(app.program.dispatch(Pressed))
  inspect(app._state.val.count, content="1")
  ignore(app.program.dispatch(Pressed))
  inspect(app._state.val.count, content="2")
  ignore(app.program.dispatch(Reset))
  inspect(app._state.val.count, content="0")
  app.program.dispose()
}

///|
test "keyboard shortcut: toggle switches listening state" {
  let runtime = @incr.Runtime()
  let app = App(runtime)

  inspect(app._state.val.listening, content="true")
  ignore(app.program.dispatch(ToggleListening))
  inspect(app._state.val.listening, content="false")
  ignore(app.program.dispatch(ToggleListening))
  inspect(app._state.val.listening, content="true")
  app.program.dispose()
}
