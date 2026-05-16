///|
test "TrackedCell wraps Signal" {
  let rt = Runtime::Runtime()
  let cell = TrackedCell::TrackedCell(rt, 42, label="test_field")
  // Access the priv signal field directly (whitebox)
  inspect(cell.signal.get(), content="42")
}

///|
test "TrackedCell label propagates to CellMeta" {
  let rt = Runtime::Runtime()
  let cell = TrackedCell::TrackedCell(rt, 0, label="my_field")
  let info = rt.cell_info(cell.id())
  debug_inspect(
    info.unwrap().label,
    content=(
      #|Some("my_field")
    ),
  )
}

///|
test "TrackedCell durability propagates" {
  let rt = Runtime::Runtime()
  let cell = TrackedCell::TrackedCell(rt, "config", durability=High)
  inspect(cell.durability(), content="High")
}
