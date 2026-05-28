///|
/// Tests for hand-built formula AST evaluation.

///|
test "typed spreadsheet: formula AST add over refs" {
  let rt = @incr.Runtime()
  let sheet = @typed_spreadsheet.Worksheet(rt, @typed_spreadsheet.SheetId(100))
  let a1 = @typed_spreadsheet.CellId(sheet.sheet_id(), "A1")
  let a2 = @typed_spreadsheet.CellId(sheet.sheet_id(), "A2")
  let b1 = @typed_spreadsheet.CellId(sheet.sheet_id(), "B1")

  inspect(
    sheet.set_input(a1, @typed_spreadsheet.CellValue::from_int(10)).is_ok(),
    content="true",
  )
  inspect(
    sheet.set_input(a2, @typed_spreadsheet.CellValue::from_int(20)).is_ok(),
    content="true",
  )

  let formula = @typed_spreadsheet.Formula::add(
    @typed_spreadsheet.Formula::cell_ref(a1),
    @typed_spreadsheet.Formula::cell_ref(a2),
  )
  let _ = sheet.set_formula_ast(
    b1,
    @typed_spreadsheet.CellType::t_int(),
    formula,
  )

  match sheet.read(b1) {
    @typed_spreadsheet.CellResult::Ok(@typed_spreadsheet.CellValue::Int(value)) =>
      inspect(value, content="30")
    _ => abort("expected Ok(Int(30)) for B1")
  }

  inspect(
    sheet.set_input(a1, @typed_spreadsheet.CellValue::from_int(15)).is_ok(),
    content="true",
  )
  match sheet.read(b1) {
    @typed_spreadsheet.CellResult::Ok(@typed_spreadsheet.CellValue::Int(value)) =>
      inspect(value, content="35")
    _ => abort("expected Ok(Int(35)) for B1 after update")
  }
}

///|
test "typed spreadsheet: formula AST follows input overwrite" {
  let rt = @incr.Runtime()
  let sheet = @typed_spreadsheet.Worksheet(rt, @typed_spreadsheet.SheetId(104))
  let source = @typed_spreadsheet.CellId(sheet.sheet_id(), "A1")
  let target = @typed_spreadsheet.CellId(sheet.sheet_id(), "B1")

  inspect(
    sheet.set_input(source, @typed_spreadsheet.CellValue::from_int(1)).is_ok(),
    content="true",
  )

  let formula = @typed_spreadsheet.Formula::add(
    @typed_spreadsheet.Formula::cell_ref(source),
    @typed_spreadsheet.Formula::literal(
      @typed_spreadsheet.CellValue::from_int(1),
    ),
  )
  let _ = sheet.set_formula_ast(
    target,
    @typed_spreadsheet.CellType::t_int(),
    formula,
  )

  match sheet.read(target) {
    @typed_spreadsheet.CellResult::Ok(@typed_spreadsheet.CellValue::Int(value)) =>
      inspect(value, content="2")
    _ => abort("expected Ok(Int(2)) for formula AST before overwrite")
  }

  inspect(
    sheet.set_input(source, @typed_spreadsheet.CellValue::from_int(10)).is_ok(),
    content="true",
  )

  match sheet.read(target) {
    @typed_spreadsheet.CellResult::Ok(@typed_spreadsheet.CellValue::Int(value)) =>
      inspect(value, content="11")
    _ => abort("expected Ok(Int(11)) for formula AST after overwrite")
  }
}

///|
test "typed spreadsheet: formula AST type error is propagated" {
  let rt = @incr.Runtime()
  let sheet = @typed_spreadsheet.Worksheet(rt, @typed_spreadsheet.SheetId(101))
  let a1 = @typed_spreadsheet.CellId(sheet.sheet_id(), "A1")
  let a2 = @typed_spreadsheet.CellId(sheet.sheet_id(), "A2")
  let b1 = @typed_spreadsheet.CellId(sheet.sheet_id(), "B1")

  inspect(
    sheet.set_input(a1, @typed_spreadsheet.CellValue::from_text("x")).is_ok(),
    content="true",
  )
  inspect(
    sheet.set_input(a2, @typed_spreadsheet.CellValue::from_int(20)).is_ok(),
    content="true",
  )

  let formula = @typed_spreadsheet.Formula::add(
    @typed_spreadsheet.Formula::cell_ref(a1),
    @typed_spreadsheet.Formula::cell_ref(a2),
  )
  let _ = sheet.set_formula_ast(
    b1,
    @typed_spreadsheet.CellType::t_int(),
    formula,
  )

  inspect(
    match sheet.read(b1) {
      @typed_spreadsheet.CellResult::TypeError(_) => true
      _ => false
    },
    content="true",
  )
}

///|
test "typed spreadsheet: formula AST undefined reference is RefError" {
  let rt = @incr.Runtime()
  let sheet = @typed_spreadsheet.Worksheet(rt, @typed_spreadsheet.SheetId(102))
  let a1 = @typed_spreadsheet.CellId(sheet.sheet_id(), "A1")
  let b1 = @typed_spreadsheet.CellId(sheet.sheet_id(), "B1")

  inspect(
    sheet.set_input(a1, @typed_spreadsheet.CellValue::from_int(20)).is_ok(),
    content="true",
  )

  let missing = @typed_spreadsheet.CellId(sheet.sheet_id(), "Z9")
  let formula = @typed_spreadsheet.Formula::add(
    @typed_spreadsheet.Formula::cell_ref(missing),
    @typed_spreadsheet.Formula::literal(
      @typed_spreadsheet.CellValue::from_int(1),
    ),
  )
  let _ = sheet.set_formula_ast(
    b1,
    @typed_spreadsheet.CellType::t_int(),
    formula,
  )

  inspect(
    match sheet.read(b1) {
      @typed_spreadsheet.CellResult::RefError(_) => true
      _ => false
    },
    content="true",
  )
}

///|
test "panic typed spreadsheet: set formula AST on disposed worksheet" {
  let rt = @incr.Runtime()
  let sheet = @typed_spreadsheet.Worksheet(rt, @typed_spreadsheet.SheetId(103))
  let b1 = @typed_spreadsheet.CellId(sheet.sheet_id(), "B1")
  sheet.dispose()

  let formula = @typed_spreadsheet.Formula::add(
    @typed_spreadsheet.Formula::literal(
      @typed_spreadsheet.CellValue::from_int(1),
    ),
    @typed_spreadsheet.Formula::literal(
      @typed_spreadsheet.CellValue::from_int(2),
    ),
  )
  let _ = sheet.set_formula_ast(
    b1,
    @typed_spreadsheet.CellType::t_int(),
    formula,
  )
}
