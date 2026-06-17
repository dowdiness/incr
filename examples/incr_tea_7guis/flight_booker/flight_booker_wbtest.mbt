///|
test "flight booker validates return date" {
  let app = App(@incr.Runtime())
  ignore(app.program.dispatch(SetFlightKind("return")))
  ignore(app.program.dispatch(SetReturnDate("2026-06-19")))
  ignore(app.program.dispatch(BookFlight))
  inspect(
    app._state.val.status,
    content="Booked return flight from 2026-06-17 to 2026-06-19.",
  )
  ignore(app.program.dispatch(SetStartDate("")))
  ignore(app.program.dispatch(SetReturnDate("")))
  inspect(dates_valid(app._state.val), content="false")
  ignore(app.program.dispatch(BookFlight))
  inspect(app._state.val.status, content="Choose valid flight dates.")
  ignore(app.program.dispatch(SetFlightKind("one-way")))
  inspect(dates_valid(app._state.val), content="false")
  app.program.dispose()
}
