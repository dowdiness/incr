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
test "typed spreadsheet: AST overwrite keeps downstream dependencies fresh" {
  let rt = @incr.Runtime()
  let sheet = @typed_spreadsheet.Worksheet(rt, @typed_spreadsheet.SheetId(104))
  let source = @typed_spreadsheet.CellId(sheet.sheet_id(), "A1")
  let target = @typed_spreadsheet.CellId(sheet.sheet_id(), "B1")
  let dependent = @typed_spreadsheet.CellId(sheet.sheet_id(), "C1")

  inspect(
    sheet.set_input(source, @typed_spreadsheet.CellValue::from_int(1)).is_ok(),
    content="true",
  )

  let first = @typed_spreadsheet.Formula::add(
    @typed_spreadsheet.Formula::cell_ref(source),
    @typed_spreadsheet.Formula::literal(
      @typed_spreadsheet.CellValue::from_int(1),
    ),
  )
  let _ = sheet.set_formula_ast(
    target,
    @typed_spreadsheet.CellType::t_int(),
    first,
  )

  let dependent_formula = @typed_spreadsheet.Formula::add(
    @typed_spreadsheet.Formula::cell_ref(target),
    @typed_spreadsheet.Formula::literal(
      @typed_spreadsheet.CellValue::from_int(1),
    ),
  )
  let _ = sheet.set_formula_ast(
    dependent,
    @typed_spreadsheet.CellType::t_int(),
    dependent_formula,
  )

  match sheet.read(dependent) {
    @typed_spreadsheet.CellResult::Ok(@typed_spreadsheet.CellValue::Int(total)) =>
      inspect(total, content="3")
    _ => abort("expected initial dependent AST result")
  }

  let updated = @typed_spreadsheet.Formula::add(
    @typed_spreadsheet.Formula::cell_ref(source),
    @typed_spreadsheet.Formula::literal(
      @typed_spreadsheet.CellValue::from_int(10),
    ),
  )
  let _ = sheet.set_formula_ast(
    target,
    @typed_spreadsheet.CellType::t_int(),
    updated,
  )

  match sheet.read(dependent) {
    @typed_spreadsheet.CellResult::Ok(@typed_spreadsheet.CellValue::Int(total)) =>
      inspect(total, content="12")
    _ => abort("expected dependent AST result after overwrite")
  }

  inspect(
    sheet.set_input(source, @typed_spreadsheet.CellValue::from_int(2)).is_ok(),
    content="true",
  )

  match sheet.read(dependent) {
    @typed_spreadsheet.CellResult::Ok(@typed_spreadsheet.CellValue::Int(total)) =>
      inspect(total, content="13")
    _ => abort("expected dependent AST result after source mutation")
  }
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
