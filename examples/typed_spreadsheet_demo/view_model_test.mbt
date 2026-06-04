///|
test "typed spreadsheet demo view model exposes fixed scenario" {
  let model = fixed_scenario_view_model()

  inspect(model.schema_version, content="1")
  inspect(model.steps.length(), content="5")
  debug_inspect(model.cells, content="[\"A1\", \"B1\"]")
  inspect(model.steps[0].operation, content="SetInput A1 = Int(10)")
  inspect(
    model.steps[1].operation,
    content="SetFormulaAst B1 : Int = (A1 + Int(1))",
  )
  inspect(model.steps[2].trace.changed.contains("B1"), content="true")
  inspect(model.steps[3].trace.unchanged.contains("B1"), content="true")
  inspect(
    model.steps[1].snapshots[0].after.last_dynamic_dependencies.contains("A1"),
    content="true",
  )
  inspect(model.steps[4].operation, content="Delete B1")
}

///|
test "typed spreadsheet demo view model captures visible before after cells" {
  let model = fixed_scenario_view_model()
  let first = model.steps[0]
  inspect(first.snapshots.length(), content="2")
  inspect(first.snapshots[0].cell, content="A1")
  inspect(first.snapshots[0].before.present, content="false")
  inspect(first.snapshots[0].after.present, content="true")
  inspect(first.snapshots[0].after.result_status, content="ok")
  inspect(first.snapshots[1].cell, content="B1")
  inspect(first.snapshots[1].before.present, content="false")
  inspect(first.snapshots[1].after.present, content="false")
  inspect(first.snapshots[1].after.result_status, content="missing")

  let delete_step = model.steps[4]
  inspect(delete_step.snapshots.length(), content="2")
  inspect(delete_step.snapshots[0].cell, content="B1")
  inspect(delete_step.snapshots[0].before.present, content="true")
  inspect(delete_step.snapshots[0].after.present, content="false")
  inspect(delete_step.snapshots[1].cell, content="A1")
  inspect(delete_step.snapshots[1].after.result, content="Ok(Int(15))")
}

///|
test "typed spreadsheet demo view model serializes as valid JSON" {
  let json = fixed_scenario_json()

  inspect(@json.valid(json), content="true")
  inspect(json.contains("\"schema_version\": 1"), content="true")
  inspect(json.contains("\"operation\": \"Delete B1\""), content="true")
  inspect(json.contains("\"result_status\": \"missing\""), content="true")
  inspect(json.contains("\"unchanged\": ["), content="true")
  inspect(json.contains("\"last_dynamic_dependencies\": ["), content="true")
}
