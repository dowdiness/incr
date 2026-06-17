///|
test "crud creates and selects people" {
  let app = App(@incr.Runtime())
  ignore(app.program.dispatch(SetName("Ada")))
  ignore(app.program.dispatch(SetSurname("Lovelace")))
  ignore(app.program.dispatch(Create))
  inspect(person_label(app._state.val.people[3]), content="Lovelace, Ada")
  debug_inspect(app._state.val.selected, content="Some(3)")
  ignore(app.program.dispatch(SetFilter("ada")))
  inspect(filtered_people(app._state.val).length(), content="1")
  debug_inspect(app._state.val.selected, content="Some(3)")
  ignore(app.program.dispatch(SetFilter("roman")))
  inspect(filtered_people(app._state.val).length(), content="1")
  debug_inspect(app._state.val.selected, content="Some(2)")
  inspect(app._state.val.name, content="Roman")
  inspect(app._state.val.surname, content="Tisch")
  ignore(app.program.dispatch(SetName("Grace")))
  ignore(app.program.dispatch(SetSurname("Hopper")))
  ignore(app.program.dispatch(Update))
  inspect(app._state.val.filter, content="")
  debug_inspect(app._state.val.selected, content="Some(2)")
  inspect(
    person_label(filtered_people(app._state.val)[2].1),
    content="Hopper, Grace",
  )
  ignore(app.program.dispatch(SetFilter("nobody")))
  inspect(filtered_people(app._state.val).length(), content="0")
  debug_inspect(app._state.val.selected, content="None")
  ignore(app.program.dispatch(SetName("Grace")))
  ignore(app.program.dispatch(SetSurname("Hopper")))
  ignore(app.program.dispatch(Create))
  inspect(app._state.val.filter, content="")
  debug_inspect(app._state.val.selected, content="Some(4)")
  inspect(
    person_label(filtered_people(app._state.val)[4].1),
    content="Hopper, Grace",
  )
  app.program.dispose()
}
