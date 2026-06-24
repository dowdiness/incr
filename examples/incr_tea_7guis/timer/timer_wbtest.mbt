///|
test "timer dispatch clamps duration" {
  let app = App(@incr.Runtime())
  ignore(app.program.dispatch(SetDuration("5000")))
  inspect(app._state.val.duration, content="5000")
  ignore(app.program.dispatch(Tick))
  inspect(app._state.val.elapsed, content="100")
  app._state.val = { ..app._state.val, elapsed: 5000, running: true }
  ignore(app.program.dispatch(SetDuration("5000")))
  inspect(app._state.val.running, content="false")
  ignore(app.program.dispatch(SetRunning(true)))
  inspect(app._state.val.running, content="false")
  app.program.dispose()
}
