///|
test "cells resolves tiny references" {
  let app = App(@incr.Runtime())
  ignore(app.program.dispatch(SetCell("A1", "42")))
  ignore(app.program.dispatch(SetCell("B1", "=A1")))
  inspect(cell_value(app._state.val, "B1"), content="42")
  match resolve_value(@tea.ValueEventId("cell:C4"), @tea.ValuePayload("=A1")) {
    Some(SetCell(id, text)) => {
      inspect(id, content="C4")
      inspect(text, content="=A1")
    }
    _ => abort("expected cell edit")
  }
  ignore(app.program.dispatch(SetCell("B1", "=A1")))
  ignore(app.program.dispatch(SetCell("C1", "=B1")))
  ignore(app.program.dispatch(SetCell("D1", "=C1")))
  ignore(app.program.dispatch(SetCell("A2", "=D1")))
  ignore(app.program.dispatch(SetCell("B2", "=A2")))
  ignore(app.program.dispatch(SetCell("C2", "=B2")))
  ignore(app.program.dispatch(SetCell("D2", "=C2")))
  ignore(app.program.dispatch(SetCell("A3", "=D2")))
  inspect(cell_value(app._state.val, "A3"), content="42")
  ignore(app.program.dispatch(SetCell("A1", "=A3")))
  inspect(cell_value(app._state.val, "A3"), content="#cycle")
  app.program.dispose()
}
