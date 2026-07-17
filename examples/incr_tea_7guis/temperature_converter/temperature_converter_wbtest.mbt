///|
test "temperature converter maps input payloads" {
  let app = App(@incr.Runtime())
  ignore(app.program.dispatch(SetCelsius("100")))
  inspect(app._state.val.fahrenheit, content="212")
  ignore(app.program.dispatch(SetCelsius("37.5")))
  inspect(app._state.val.fahrenheit, content="99.5")
  ignore(app.program.dispatch(SetCelsius("1")))
  inspect(app._state.val.fahrenheit, content="33.8")
  match
    resolve_value(@tea.ValueEventId("fahrenheit"), @tea.ValuePayload("32")) {
    Some(SetFahrenheit(value)) => inspect(value, content="32")
    _ => abort("expected fahrenheit message")
  }
  app.program.dispose()
}
