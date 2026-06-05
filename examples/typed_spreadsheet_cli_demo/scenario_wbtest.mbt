///|
test "typed spreadsheet CLI scenario captures fixed trace story" {
  let steps = run_scenario()
  inspect(steps.length(), content="5")
  inspect(format_op(steps[0].operation), content="SetInput A1 = Int(10)")
  inspect(
    format_op(steps[1].operation),
    content="SetFormulaAst B1 : Int = (A1 + Int(1))",
  )
  inspect(format_cell_ids(steps[2].trace.changed), content="[B1]")
  inspect(format_cell_ids(steps[3].trace.changed), content="[]")
  inspect(format_cell_ids(steps[3].trace.unchanged), content="[]")
  inspect(format_op(steps[4].operation), content="Delete B1")
}

///|
test "typed spreadsheet CLI scenario renders text and JSON" {
  let text = render_scenario(TextFormat)
  inspect(text.contains("#3 SetInput A1 = Int(15)"), content="true")
  inspect(text.contains("  changed: [B1]"), content="true")
  inspect(text.contains("#4 SetInput A1 = Int(15)"), content="true")
  inspect(text.contains("  unchanged: []"), content="true")
  let json = render_scenario(JsonFormat)
  inspect(@json.valid(json), content="true")
  inspect(json.contains("SetFormulaAst B1 : Int"), content="true")
  inspect(
    json.contains("\"dependency_shape\": \"applicative\""),
    content="true",
  )
  inspect(json.contains("\"unchanged\": ["), content="true")
  inspect(json.contains("\"B1\""), content="true")
}

///|
test "typed spreadsheet CLI rejects unsupported format without aborting" {
  let output = render_cli(argv=["--format", "yaml"])
  inspect(
    output.contains(
      "error: unsupported --format 'yaml' (expected text or json)",
    ),
    content="true",
  )
  inspect(
    output.contains("Usage: typed-spreadsheet-demo [options]"),
    content="true",
  )
}
