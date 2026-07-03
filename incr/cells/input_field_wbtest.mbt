///|
test "InputField wraps Input" {
  let rt = Runtime::Runtime()
  let cell = InputField(rt, 42, label="test_field")
  // Access the priv input field directly (whitebox)
  inspect(cell.input.get(), content="42")
}

///|
test "InputField label propagates to CellMeta" {
  let rt = Runtime::Runtime()
  let cell = InputField(rt, 0, label="my_field")
  let info = rt.cell_info(cell.id())
  debug_inspect(
    info.unwrap().label,
    content=(
      #|Some("my_field")
    ),
  )
}

///|
test "InputField durability propagates" {
  let rt = Runtime::Runtime()
  let cell = InputField(rt, "config", durability=High)
  inspect(cell.durability(), content="High")
}
