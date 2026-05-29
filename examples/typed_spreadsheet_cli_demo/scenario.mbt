///|
fn run_scenario() -> Array[@demo.WorksheetStepResult] {
  let runtime = @incr.Runtime()
  let sheet = @typed_spreadsheet.Worksheet(runtime, SheetId(1))
  let a1 = @typed_spreadsheet.CellId(sheet.sheet_id(), "A1")
  let b1 = @typed_spreadsheet.CellId(sheet.sheet_id(), "B1")
  let steps = []
  steps.push(@demo.run_op(sheet, must_parse_cell_text_op(a1, "10")))
  steps.push(@demo.run_op(sheet, must_parse_cell_text_op(b1, "=A1 + 1")))
  steps.push(
    @demo.run_op(sheet, must_parse_cell_text_op(a1, "15"), capture=[b1]),
  )
  steps.push(
    @demo.run_op(sheet, must_parse_cell_text_op(a1, "15"), capture=[b1]),
  )
  steps.push(@demo.run_op(sheet, Delete(b1)))
  steps
}

///|
fn must_parse_cell_text_op(
  target : @typed_spreadsheet.CellId,
  text : String,
) -> @demo.SheetOp {
  match @demo.parse_cell_text_op(target, text) {
    Ok(operation) => operation
    Err(error) => {
      let detail = repr(error)
      abort("fixed typed spreadsheet demo parse failed: " + detail)
    }
  }
}
