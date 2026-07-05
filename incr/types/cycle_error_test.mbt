///|
test "path returns a copy: mutation cannot desync format_path" {
  let cell = CellId::{ runtime_id: RuntimeId(0), id: 1 }
  let other = CellId::{ runtime_id: RuntimeId(0), id: 2 }
  let e = CycleError::new(cell, [cell, other, cell], [
    Some("a"),
    None,
    Some("a"),
  ])
  let stolen = e.path()
  stolen.push(other)
  stolen.push(other)
  // The stored path is untouched: length stays 3 and format_path still
  // renders exactly the label snapshot taken at construction.
  inspect(e.path().length(), content="3")
  inspect(e.format_path(), content="Cycle detected: a → Cell[2] → a")
}
