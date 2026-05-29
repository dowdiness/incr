///|
fn run_scenario() -> Array[@demo.WorksheetStepResult] {
  let runtime = @incr.Runtime()
  let sheet = @typed_spreadsheet.Worksheet(runtime, SheetId(1))
  let a1 = @typed_spreadsheet.CellId(sheet.sheet_id(), "A1")
  let b1 = @typed_spreadsheet.CellId(sheet.sheet_id(), "B1")
  let add_one = add_one_formula(a1)
  let steps = []
  steps.push(
    @demo.run_op(
      sheet,
      SetInput(a1, @typed_spreadsheet.CellValue::from_int(10)),
    ),
  )
  steps.push(
    @demo.run_op(
      sheet,
      SetFormulaAst(b1, @typed_spreadsheet.CellType::t_int(), add_one),
    ),
  )
  steps.push(
    @demo.run_op(
      sheet,
      SetInput(a1, @typed_spreadsheet.CellValue::from_int(15)),
      capture=[b1],
    ),
  )
  steps.push(
    @demo.run_op(
      sheet,
      SetInput(a1, @typed_spreadsheet.CellValue::from_int(15)),
      capture=[b1],
    ),
  )
  steps.push(@demo.run_op(sheet, Delete(b1)))
  steps
}

///|
fn add_one_formula(
  source : @typed_spreadsheet.CellId,
) -> @typed_spreadsheet.Formula {
  @typed_spreadsheet.Formula::add(
    @typed_spreadsheet.Formula::cell_ref(source),
    @typed_spreadsheet.Formula::literal(
      @typed_spreadsheet.CellValue::from_int(1),
    ),
  )
}
