///|
/// Runs the fixed five-step typed spreadsheet demo scenario.
///
/// The scenario is shared by the CLI and Web demos so both presentations stay
/// focused on rendering rather than reconstructing worksheet operations.
pub fn run_fixed_scenario() -> Array[WorksheetStepResult] {
  run_fixed_scenario_with_visible_capture(false)
}

///|
fn run_fixed_scenario_for_view_model() -> Array[WorksheetStepResult] {
  run_fixed_scenario_with_visible_capture(true)
}

///|
fn run_fixed_scenario_with_visible_capture(
  capture_visible_cells : Bool,
) -> Array[WorksheetStepResult] {
  let runtime = @incr.Runtime()
  let sheet = @typed_spreadsheet.Worksheet(runtime, SheetId(1))
  let a1 = @typed_spreadsheet.CellId(sheet.sheet_id(), "A1")
  let b1 = @typed_spreadsheet.CellId(sheet.sheet_id(), "B1")
  let visible_cells = [a1, b1]
  let steps = []
  steps.push(
    run_op(
      sheet,
      must_parse_cell_text_op(a1, "10"),
      capture=scenario_capture(capture_visible_cells, visible_cells, []),
    ),
  )
  steps.push(
    run_op(
      sheet,
      must_parse_cell_text_op(b1, "=A1 + 1"),
      capture=scenario_capture(capture_visible_cells, visible_cells, []),
    ),
  )
  steps.push(
    run_op(
      sheet,
      must_parse_cell_text_op(a1, "15"),
      capture=scenario_capture(capture_visible_cells, visible_cells, [b1]),
    ),
  )
  steps.push(
    run_op(
      sheet,
      must_parse_cell_text_op(a1, "15"),
      capture=scenario_capture(capture_visible_cells, visible_cells, [b1]),
    ),
  )
  steps.push(
    run_op(
      sheet,
      Delete(b1),
      capture=scenario_capture(capture_visible_cells, visible_cells, []),
    ),
  )
  steps
}

///|
fn scenario_capture(
  capture_visible_cells : Bool,
  visible_cells : Array[@typed_spreadsheet.CellId],
  fallback : Array[@typed_spreadsheet.CellId],
) -> Array[@typed_spreadsheet.CellId] {
  if capture_visible_cells {
    visible_cells
  } else {
    fallback
  }
}

///|
fn must_parse_cell_text_op(
  target : @typed_spreadsheet.CellId,
  text : String,
) -> SheetOp {
  match parse_cell_text_op(target, text) {
    Ok(operation) => operation
    Err(error) => {
      let detail = repr(error)
      abort("fixed typed spreadsheet demo parse failed: " + detail)
    }
  }
}
