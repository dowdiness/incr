///|
fn format_op(operation : @demo.SheetOp) -> String {
  @demo.format_op(operation)
}

///|
fn format_outcome(outcome : @demo.OpOutcome) -> String {
  @demo.format_outcome(outcome)
}

///|
fn format_snapshot(snapshot : @typed_spreadsheet.CellSnapshot) -> String {
  @demo.format_snapshot(snapshot)
}

///|
fn format_cell_ids(ids : Array[@typed_spreadsheet.CellId]) -> String {
  @demo.format_cell_ids(ids)
}

///|
fn cell_id_to_string(id : @typed_spreadsheet.CellId) -> String {
  @demo.cell_id_to_string(id)
}

///|
fn format_cell_result(result : @typed_spreadsheet.CellResult) -> String {
  @demo.format_cell_result(result)
}

///|
fn cell_id_strings(ids : Array[@typed_spreadsheet.CellId]) -> Array[String] {
  @demo.cell_id_strings(ids)
}

///|
fn snapshot_kind(snapshot : @typed_spreadsheet.CellSnapshot) -> String {
  @demo.snapshot_kind(snapshot)
}
