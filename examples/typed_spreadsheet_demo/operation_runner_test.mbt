///|
test "typed spreadsheet demo op: SetInput captures before/after snapshot" {
  let sheet = new_sheet(1)
  let a1 = @typed_spreadsheet.CellId(sheet.sheet_id(), "A1")

  let result = run_op(
    sheet,
    SetInput(a1, @typed_spreadsheet.CellValue::from_int(10)),
  )

  match result.outcome {
    SetInput(Ok(Int(value))) => inspect(value, content="10")
    _ => abort("expected SetInput Ok(Int(10)) outcome")
  }
  inspect(result.cell_snapshots.length(), content="1")
  let change = result.cell_snapshots[0]
  inspect(change.before.present, content="false")
  inspect(change.after.present, content="true")
  match change.after.result {
    Ok(Int(value)) => inspect(value, content="10")
    _ => abort("expected after snapshot to contain Int(10)")
  }
  inspect(result.trace.recomputed.length(), content="0")
}

///|
test "typed spreadsheet demo op: SetFormulaAst exposes static refs and trace" {
  let sheet = new_sheet(2)
  let a1 = @typed_spreadsheet.CellId(sheet.sheet_id(), "A1")
  let b1 = @typed_spreadsheet.CellId(sheet.sheet_id(), "B1")
  inspect(
    sheet.set_input(a1, @typed_spreadsheet.CellValue::from_int(5)).is_ok(),
    content="true",
  )

  let result = run_op(
    sheet,
    SetFormulaAst(b1, @typed_spreadsheet.CellType::t_int(), add_one_formula(a1)),
  )

  match result.outcome {
    SetFormulaAst(Ok(_)) => inspect(true, content="true")
    _ => abort("expected SetFormulaAst Ok outcome")
  }
  inspect(result.trace.recomputed.contains(b1), content="true")
  inspect(result.trace.changed.contains(b1), content="true")
  inspect(result.cell_snapshots.length(), content="2")
  let formula_change = result.cell_snapshots[0]
  inspect(formula_change.id == b1, content="true")
  inspect(formula_change.after.static_references.contains(a1), content="true")
  inspect(formula_change.after.installed_dependencies.length(), content="0")
  inspect(
    formula_change.after.last_dynamic_dependencies.contains(a1),
    content="true",
  )
  match formula_change.after.result {
    Ok(Int(value)) => inspect(value, content="6")
    _ => abort("expected formula snapshot to contain Int(6)")
  }
}

///|
test "typed spreadsheet demo op: dependency update traces changed formula" {
  let sheet = new_sheet(3)
  let a1 = @typed_spreadsheet.CellId(sheet.sheet_id(), "A1")
  let b1 = @typed_spreadsheet.CellId(sheet.sheet_id(), "B1")
  install_add_one(sheet, a1, b1, 1)

  let result = run_op(
    sheet,
    SetInput(a1, @typed_spreadsheet.CellValue::from_int(2)),
    capture=[b1],
  )

  inspect(result.trace.recomputed.contains(b1), content="true")
  inspect(result.trace.changed.contains(b1), content="true")
  let formula_change = result.cell_snapshots[1]
  assert_snapshot_int(formula_change.before, 2)
  assert_snapshot_int(formula_change.after, 3)
}

///|
test "typed spreadsheet demo op: batched dependency update traces after commit" {
  let sheet = new_sheet(6)
  let a1 = @typed_spreadsheet.CellId(sheet.sheet_id(), "A1")
  let b1 = @typed_spreadsheet.CellId(sheet.sheet_id(), "B1")
  install_add_one(sheet, a1, b1, 1)

  let result = run_batched_op(
    sheet,
    SetInput(a1, @typed_spreadsheet.CellValue::from_int(2)),
    capture=[b1],
  )

  inspect(result.trace.recomputed.contains(b1), content="true")
  inspect(result.trace.changed.contains(b1), content="true")
  let formula_change = result.cell_snapshots[1]
  assert_snapshot_int(formula_change.before, 2)
  assert_snapshot_int(formula_change.after, 3)
}

///|
test "typed spreadsheet demo op: same-value dependency update traces unchanged formula" {
  let sheet = new_sheet(4)
  let a1 = @typed_spreadsheet.CellId(sheet.sheet_id(), "A1")
  let b1 = @typed_spreadsheet.CellId(sheet.sheet_id(), "B1")
  install_add_one(sheet, a1, b1, 1)

  let result = run_op(
    sheet,
    SetInput(a1, @typed_spreadsheet.CellValue::from_int(1)),
    capture=[b1],
  )

  inspect(result.trace.recomputed.contains(b1), content="true")
  inspect(result.trace.changed.contains(b1), content="false")
  inspect(result.trace.unchanged.contains(b1), content="true")
  let formula_change = result.cell_snapshots[1]
  assert_snapshot_int(formula_change.before, 2)
  assert_snapshot_int(formula_change.after, 2)
}

///|
test "typed spreadsheet demo op: Delete returns missing after snapshot" {
  let sheet = new_sheet(5)
  let a1 = @typed_spreadsheet.CellId(sheet.sheet_id(), "A1")
  let b1 = @typed_spreadsheet.CellId(sheet.sheet_id(), "B1")
  install_add_one(sheet, a1, b1, 1)

  let result = run_op(sheet, Delete(b1))

  match result.outcome {
    Delete(Ok(Blank)) => inspect(true, content="true")
    _ => abort("expected Delete Ok(Blank) outcome")
  }
  inspect(result.trace.recomputed.contains(b1), content="false")
  let change = result.cell_snapshots[0]
  inspect(change.before.present, content="true")
  inspect(change.after.present, content="false")
  match change.after.result {
    RefError(_) => inspect(true, content="true")
    _ => abort("expected deleted cell after snapshot to be RefError")
  }
}

///|
fn new_sheet(id : Int) -> @typed_spreadsheet.Worksheet {
  let rt = @incr.Runtime()
  let sheet_id = @typed_spreadsheet.SheetId(id)
  Worksheet(rt, sheet_id)
}

///|
fn install_add_one(
  sheet : @typed_spreadsheet.Worksheet,
  source : @typed_spreadsheet.CellId,
  target : @typed_spreadsheet.CellId,
  value : Int,
) -> Unit {
  if !sheet
    .set_input(source, @typed_spreadsheet.CellValue::from_int(value))
    .is_ok() {
    abort("expected input install to succeed")
  }
  match
    sheet.set_formula_ast(
      target,
      @typed_spreadsheet.CellType::t_int(),
      add_one_formula(source),
    ) {
    Ok(_) => ()
    Err(_) => abort("expected formula install to succeed")
  }
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

///|
fn assert_snapshot_int(
  snapshot : @typed_spreadsheet.CellSnapshot,
  expected : Int,
) -> Unit {
  match snapshot.result {
    Ok(Int(value)) =>
      if value != expected {
        abort("unexpected snapshot Int value")
      }
    _ => abort("expected snapshot to contain an Int value")
  }
}
