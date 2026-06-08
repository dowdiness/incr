///|
/// Tests for hand-built formula AST evaluation.

///|
enum ExpectedFormulaAstQueryError {
  ExpectForeignCellId
  ExpectMissingCell
  ExpectDeletedCell
  ExpectNotFormula
  ExpectOpaqueFormula
}

///|
fn formula_ast_error_is(
  sheet : @typed_spreadsheet.Worksheet,
  id : @typed_spreadsheet.CellId,
  expected : ExpectedFormulaAstQueryError,
) -> Bool {
  match (sheet.formula_ast(id), expected) {
    (
      Err(@typed_spreadsheet.FormulaAstQueryError::ForeignCellId(actual)),
      ExpectForeignCellId,
    ) => actual == id
    (
      Err(@typed_spreadsheet.FormulaAstQueryError::MissingCell(actual)),
      ExpectMissingCell,
    ) => actual == id
    (
      Err(@typed_spreadsheet.FormulaAstQueryError::DeletedCell(actual)),
      ExpectDeletedCell,
    ) => actual == id
    (
      Err(@typed_spreadsheet.FormulaAstQueryError::NotFormula(actual)),
      ExpectNotFormula,
    ) => actual == id
    (
      Err(@typed_spreadsheet.FormulaAstQueryError::OpaqueFormula(actual)),
      ExpectOpaqueFormula,
    ) => actual == id
    _ => false
  }
}

///|
test "typed spreadsheet: formula dependency shape classifies static expressions" {
  let sheet_id = @typed_spreadsheet.SheetId(1200)
  let a1 = @typed_spreadsheet.CellId(sheet_id, "A1")
  let a2 = @typed_spreadsheet.CellId(sheet_id, "A2")
  let formula = @typed_spreadsheet.Formula::add(
    @typed_spreadsheet.Formula::cell_ref(a1),
    @typed_spreadsheet.Formula::mul(
      @typed_spreadsheet.Formula::cell_ref(a2),
      @typed_spreadsheet.Formula::literal(
        @typed_spreadsheet.CellValue::from_int(2),
      ),
    ),
  )

  inspect(
    formula.dependency_shape() ==
    @typed_spreadsheet.FormulaDependencyShape::Applicative,
    content="true",
  )
}

///|
test "typed spreadsheet: formula dependency shape classifies conditionals" {
  let sheet_id = @typed_spreadsheet.SheetId(1201)
  let condition = @typed_spreadsheet.CellId(sheet_id, "A1")
  let true_value = @typed_spreadsheet.CellId(sheet_id, "A2")
  let false_value = @typed_spreadsheet.CellId(sheet_id, "A3")
  let formula = @typed_spreadsheet.Formula::if_(
    @typed_spreadsheet.Formula::cell_ref(condition),
    @typed_spreadsheet.Formula::cell_ref(true_value),
    @typed_spreadsheet.Formula::cell_ref(false_value),
  )

  inspect(
    formula.dependency_shape() ==
    @typed_spreadsheet.FormulaDependencyShape::Selective,
    content="true",
  )
}

///|
test "typed spreadsheet: dynamic dependency shape is reserved for future address formulas" {
  let reserved = @typed_spreadsheet.FormulaDependencyShape::Dynamic
  inspect(
    reserved == @typed_spreadsheet.FormulaDependencyShape::Dynamic,
    content="true",
  )
}

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
      inspect(value, content="999")
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
test "typed spreadsheet: formula_ast returns AST-backed formula" {
  let rt = @incr.Runtime()
  let sheet = @typed_spreadsheet.Worksheet(rt, @typed_spreadsheet.SheetId(1300))
  let target = @typed_spreadsheet.CellId(sheet.sheet_id(), "B1")

  let formula = @typed_spreadsheet.Formula::add(
    @typed_spreadsheet.Formula::literal(
      @typed_spreadsheet.CellValue::from_int(1),
    ),
    @typed_spreadsheet.Formula::literal(
      @typed_spreadsheet.CellValue::from_int(2),
    ),
  )
  inspect(
    sheet.set_formula_ast(target, @typed_spreadsheet.CellType::t_int(), formula) ==
    Ok(()),
    content="true",
  )
  inspect(sheet.formula_ast(target) == Ok(formula), content="true")
}

///|
test "typed spreadsheet: formula_ast reports cell state errors" {
  let rt = @incr.Runtime()
  let sheet = @typed_spreadsheet.Worksheet(rt, @typed_spreadsheet.SheetId(1301))
  let input = @typed_spreadsheet.CellId(sheet.sheet_id(), "A1")
  let deleted = @typed_spreadsheet.CellId(sheet.sheet_id(), "B1")
  let closure = @typed_spreadsheet.CellId(sheet.sheet_id(), "C1")
  let missing = @typed_spreadsheet.CellId(sheet.sheet_id(), "Z9")
  let foreign = @typed_spreadsheet.CellId(
    @typed_spreadsheet.SheetId(1302),
    "A1",
  )

  inspect(
    sheet.set_input(input, @typed_spreadsheet.CellValue::from_int(1)).is_ok(),
    content="true",
  )
  inspect(formula_ast_error_is(sheet, input, ExpectNotFormula), content="true")
  inspect(
    formula_ast_error_is(sheet, foreign, ExpectForeignCellId),
    content="true",
  )
  inspect(
    formula_ast_error_is(sheet, missing, ExpectMissingCell),
    content="true",
  )

  inspect(
    sheet.set_input(deleted, @typed_spreadsheet.CellValue::from_int(2)).is_ok(),
    content="true",
  )
  inspect(sheet.delete(deleted).is_ok(), content="true")
  inspect(
    formula_ast_error_is(sheet, deleted, ExpectDeletedCell),
    content="true",
  )
  inspect(sheet.compact_deleted_cells(), content="1")
  inspect(
    formula_ast_error_is(sheet, deleted, ExpectDeletedCell),
    content="true",
  )

  inspect(
    sheet.set_formula(closure, @typed_spreadsheet.CellType::t_int(), [], fn(
      _deps,
    ) {
      @typed_spreadsheet.CellResult::ok(
        @typed_spreadsheet.CellValue::from_int(3),
      )
    }) ==
    Ok(()),
    content="true",
  )
  inspect(
    formula_ast_error_is(sheet, closure, ExpectOpaqueFormula),
    content="true",
  )
}

///|
test "typed spreadsheet: formula_ast follows formula identity replacement" {
  let rt = @incr.Runtime()
  let sheet = @typed_spreadsheet.Worksheet(rt, @typed_spreadsheet.SheetId(1303))
  let target = @typed_spreadsheet.CellId(sheet.sheet_id(), "B1")

  let first = @typed_spreadsheet.Formula::literal(
    @typed_spreadsheet.CellValue::from_int(1),
  )
  let second = @typed_spreadsheet.Formula::add(
    @typed_spreadsheet.Formula::literal(
      @typed_spreadsheet.CellValue::from_int(1),
    ),
    @typed_spreadsheet.Formula::literal(
      @typed_spreadsheet.CellValue::from_int(2),
    ),
  )
  let third = @typed_spreadsheet.Formula::mul(
    @typed_spreadsheet.Formula::literal(
      @typed_spreadsheet.CellValue::from_int(2),
    ),
    @typed_spreadsheet.Formula::literal(
      @typed_spreadsheet.CellValue::from_int(3),
    ),
  )

  let _ = sheet.set_formula_ast(
    target,
    @typed_spreadsheet.CellType::t_int(),
    first,
  )
  inspect(sheet.formula_ast(target) == Ok(first), content="true")

  let _ = sheet.set_formula_ast(
    target,
    @typed_spreadsheet.CellType::t_int(),
    second,
  )
  inspect(sheet.formula_ast(target) == Ok(second), content="true")
  inspect(sheet.formula_ast(target) != Ok(first), content="true")

  inspect(
    sheet.set_formula(target, @typed_spreadsheet.CellType::t_int(), [], fn(
      _deps,
    ) {
      @typed_spreadsheet.CellResult::ok(
        @typed_spreadsheet.CellValue::from_int(4),
      )
    }) ==
    Ok(()),
    content="true",
  )
  inspect(
    formula_ast_error_is(sheet, target, ExpectOpaqueFormula),
    content="true",
  )

  let _ = sheet.set_formula_ast(
    target,
    @typed_spreadsheet.CellType::t_int(),
    third,
  )
  inspect(sheet.formula_ast(target) == Ok(third), content="true")
  inspect(sheet.formula_ast(target) != Ok(second), content="true")
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
test "typed spreadsheet: formula AST slot survives Runtime::gc with input dependency" {
  let rt = @incr.Runtime()
  let sheet = @typed_spreadsheet.Worksheet(rt, @typed_spreadsheet.SheetId(1280))
  let a1 = @typed_spreadsheet.CellId(sheet.sheet_id(), "A1")
  let b1 = @typed_spreadsheet.CellId(sheet.sheet_id(), "B1")

  inspect(
    sheet.set_input(a1, @typed_spreadsheet.CellValue::from_int(1)).is_ok(),
    content="true",
  )

  let formula = @typed_spreadsheet.Formula::add(
    @typed_spreadsheet.Formula::cell_ref(a1),
    @typed_spreadsheet.Formula::literal(
      @typed_spreadsheet.CellValue::from_int(1),
    ),
  )
  let _ = sheet.set_formula_ast(
    b1,
    @typed_spreadsheet.CellType::t_int(),
    formula,
  )

  rt.gc()

  match sheet.read(b1) {
    @typed_spreadsheet.CellResult::Ok(@typed_spreadsheet.CellValue::Int(value)) =>
      inspect(value, content="2")
    _ => abort("expected formula slot to survive Runtime::gc")
  }

  inspect(
    sheet.set_input(a1, @typed_spreadsheet.CellValue::from_int(2)).is_ok(),
    content="true",
  )
  match sheet.read(b1) {
    @typed_spreadsheet.CellResult::Ok(@typed_spreadsheet.CellValue::Int(value)) =>
      inspect(value, content="3")
    _ => abort("expected formula dependency to survive Runtime::gc")
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
  inspect(
    match
      sheet.set_formula_ast(b1, @typed_spreadsheet.CellType::t_int(), formula) {
      Ok(_) => true
      _ => false
    },
    content="true",
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
test "typed spreadsheet: formula AST operator mismatch is runtime checked" {
  let rt = @incr.Runtime()
  let sheet = @typed_spreadsheet.Worksheet(rt, @typed_spreadsheet.SheetId(115))
  let b1 = @typed_spreadsheet.CellId(sheet.sheet_id(), "B1")

  let formula = @typed_spreadsheet.Formula::add(
    @typed_spreadsheet.Formula::literal(
      @typed_spreadsheet.CellValue::from_text("x"),
    ),
    @typed_spreadsheet.Formula::literal(
      @typed_spreadsheet.CellValue::from_int(1),
    ),
  )
  inspect(
    match
      sheet.set_formula_ast(b1, @typed_spreadsheet.CellType::t_int(), formula) {
      Ok(_) => true
      _ => false
    },
    content="true",
  )

  inspect(
    match sheet.read(b1) {
      @typed_spreadsheet.CellResult::TypeError(message) => {
        inspect(message, content="Add requires Int on the left side")
        true
      }
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
  let (_, trace) = sheet.trace(fn() {
    let _ = sheet.set_formula_ast(
      target,
      @typed_spreadsheet.CellType::t_int(),
      updated,
    )
    ()
  })

  inspect(trace.changed.contains(target), content="true")
  inspect(trace.changed.contains(dependent), content="true")

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
test "typed spreadsheet: same AST reinstall is worksheet no-op" {
  let rt = @incr.Runtime()
  let sheet = @typed_spreadsheet.Worksheet(rt, @typed_spreadsheet.SheetId(124))
  let source = @typed_spreadsheet.CellId(sheet.sheet_id(), "A1")
  let target = @typed_spreadsheet.CellId(sheet.sheet_id(), "B1")
  let dependent = @typed_spreadsheet.CellId(sheet.sheet_id(), "C1")

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

  let same_formula = @typed_spreadsheet.Formula::add(
    @typed_spreadsheet.Formula::cell_ref(source),
    @typed_spreadsheet.Formula::literal(
      @typed_spreadsheet.CellValue::from_int(1),
    ),
  )
  let (_, trace) = sheet.trace(fn() {
    let _ = sheet.set_formula_ast(
      target,
      @typed_spreadsheet.CellType::t_int(),
      same_formula,
    )
    ()
  })

  inspect(trace.recomputed.contains(target), content="false")
  inspect(trace.recomputed.contains(dependent), content="false")
  inspect(trace.changed.contains(target), content="false")
  inspect(trace.changed.contains(dependent), content="false")
  inspect(trace.unchanged.contains(target), content="false")
  inspect(trace.unchanged.contains(dependent), content="false")
  match sheet.read(dependent) {
    @typed_spreadsheet.CellResult::Ok(@typed_spreadsheet.CellValue::Int(total)) =>
      inspect(total, content="3")
    _ => abort("expected dependent AST result after no-op reinstall")
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
test "typed spreadsheet: formula AST mul computes products" {
  let rt = @incr.Runtime()
  let sheet = @typed_spreadsheet.Worksheet(rt, @typed_spreadsheet.SheetId(105))
  let a1 = @typed_spreadsheet.CellId(sheet.sheet_id(), "A1")
  let a2 = @typed_spreadsheet.CellId(sheet.sheet_id(), "A2")
  let b1 = @typed_spreadsheet.CellId(sheet.sheet_id(), "B1")

  inspect(
    sheet.set_input(a1, @typed_spreadsheet.CellValue::from_int(3)).is_ok(),
    content="true",
  )
  inspect(
    sheet.set_input(a2, @typed_spreadsheet.CellValue::from_int(4)).is_ok(),
    content="true",
  )

  let formula = @typed_spreadsheet.Formula::mul(
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
      inspect(value, content="12")
    _ => abort("expected Ok(Int(12)) for formula AST mul")
  }
}

///|
test "typed spreadsheet: formula AST eq computes booleans" {
  let rt = @incr.Runtime()
  let sheet = @typed_spreadsheet.Worksheet(rt, @typed_spreadsheet.SheetId(106))
  let left = @typed_spreadsheet.CellId(sheet.sheet_id(), "A1")
  let right = @typed_spreadsheet.CellId(sheet.sheet_id(), "A2")
  let b1 = @typed_spreadsheet.CellId(sheet.sheet_id(), "B1")

  inspect(
    sheet.set_input(left, @typed_spreadsheet.CellValue::from_int(7)).is_ok(),
    content="true",
  )
  inspect(
    sheet.set_input(right, @typed_spreadsheet.CellValue::from_int(7)).is_ok(),
    content="true",
  )

  let formula = @typed_spreadsheet.Formula::eq(
    @typed_spreadsheet.Formula::cell_ref(left),
    @typed_spreadsheet.Formula::cell_ref(right),
  )
  let _ = sheet.set_formula_ast(
    b1,
    @typed_spreadsheet.CellType::t_bool(),
    formula,
  )

  match sheet.read(b1) {
    @typed_spreadsheet.CellResult::Ok(@typed_spreadsheet.CellValue::Bool(value)) =>
      inspect(value, content="true")
    _ => abort("expected Ok(Bool(true)) for formula AST eq")
  }

  inspect(
    sheet.set_input(right, @typed_spreadsheet.CellValue::from_int(9)).is_ok(),
    content="true",
  )

  match sheet.read(b1) {
    @typed_spreadsheet.CellResult::Ok(@typed_spreadsheet.CellValue::Bool(value)) =>
      inspect(value, content="false")
    _ => abort("expected Ok(Bool(false)) after eq input update")
  }
}

///|
test "typed spreadsheet: formula AST gt computes booleans" {
  let rt = @incr.Runtime()
  let sheet = @typed_spreadsheet.Worksheet(rt, @typed_spreadsheet.SheetId(107))
  let left = @typed_spreadsheet.CellId(sheet.sheet_id(), "A1")
  let right = @typed_spreadsheet.CellId(sheet.sheet_id(), "A2")
  let b1 = @typed_spreadsheet.CellId(sheet.sheet_id(), "B1")

  inspect(
    sheet.set_input(left, @typed_spreadsheet.CellValue::from_int(10)).is_ok(),
    content="true",
  )
  inspect(
    sheet.set_input(right, @typed_spreadsheet.CellValue::from_int(4)).is_ok(),
    content="true",
  )

  let formula = @typed_spreadsheet.Formula::gt(
    @typed_spreadsheet.Formula::cell_ref(left),
    @typed_spreadsheet.Formula::cell_ref(right),
  )
  let _ = sheet.set_formula_ast(
    b1,
    @typed_spreadsheet.CellType::t_bool(),
    formula,
  )

  match sheet.read(b1) {
    @typed_spreadsheet.CellResult::Ok(@typed_spreadsheet.CellValue::Bool(value)) =>
      inspect(value, content="true")
    _ => abort("expected Ok(Bool(true)) for formula AST gt")
  }

  inspect(
    sheet.set_input(left, @typed_spreadsheet.CellValue::from_int(1)).is_ok(),
    content="true",
  )

  match sheet.read(b1) {
    @typed_spreadsheet.CellResult::Ok(@typed_spreadsheet.CellValue::Bool(value)) =>
      inspect(value, content="false")
    _ => abort("expected Ok(Bool(false)) after gt input update")
  }
}

///|
test "typed spreadsheet: formula AST if branches by bool condition" {
  let rt = @incr.Runtime()
  let sheet = @typed_spreadsheet.Worksheet(rt, @typed_spreadsheet.SheetId(108))
  let left = @typed_spreadsheet.CellId(sheet.sheet_id(), "A1")
  let true_value = @typed_spreadsheet.CellId(sheet.sheet_id(), "A2")
  let false_value = @typed_spreadsheet.CellId(sheet.sheet_id(), "A3")
  let b1 = @typed_spreadsheet.CellId(sheet.sheet_id(), "B1")

  inspect(
    sheet.set_input(left, @typed_spreadsheet.CellValue::from_int(1)).is_ok(),
    content="true",
  )
  inspect(
    sheet
    .set_input(true_value, @typed_spreadsheet.CellValue::from_int(1))
    .is_ok(),
    content="true",
  )
  inspect(
    sheet
    .set_input(false_value, @typed_spreadsheet.CellValue::from_int(2))
    .is_ok(),
    content="true",
  )

  let formula = @typed_spreadsheet.Formula::if_(
    @typed_spreadsheet.Formula::gt(
      @typed_spreadsheet.Formula::cell_ref(left),
      @typed_spreadsheet.Formula::literal(
        @typed_spreadsheet.CellValue::from_int(0),
      ),
    ),
    @typed_spreadsheet.Formula::cell_ref(true_value),
    @typed_spreadsheet.Formula::cell_ref(false_value),
  )
  let _ = sheet.set_formula_ast(
    b1,
    @typed_spreadsheet.CellType::t_int(),
    formula,
  )

  match sheet.read(b1) {
    @typed_spreadsheet.CellResult::Ok(@typed_spreadsheet.CellValue::Int(value)) =>
      inspect(value, content="1")
    _ => abort("expected true branch value for formula AST if")
  }

  inspect(
    sheet.set_input(left, @typed_spreadsheet.CellValue::from_int(0)).is_ok(),
    content="true",
  )

  match sheet.read(b1) {
    @typed_spreadsheet.CellResult::Ok(@typed_spreadsheet.CellValue::Int(value)) =>
      inspect(value, content="2")
    _ => abort("expected false branch value for formula AST if")
  }
}

///|
test "typed spreadsheet: formula AST mul rejects non-int terms" {
  let rt = @incr.Runtime()
  let sheet = @typed_spreadsheet.Worksheet(rt, @typed_spreadsheet.SheetId(109))
  let a1 = @typed_spreadsheet.CellId(sheet.sheet_id(), "A1")
  let a2 = @typed_spreadsheet.CellId(sheet.sheet_id(), "A2")
  let b1 = @typed_spreadsheet.CellId(sheet.sheet_id(), "B1")

  inspect(
    sheet.set_input(a1, @typed_spreadsheet.CellValue::from_int(3)).is_ok(),
    content="true",
  )
  inspect(
    sheet.set_input(a2, @typed_spreadsheet.CellValue::from_text("x")).is_ok(),
    content="true",
  )

  let formula = @typed_spreadsheet.Formula::mul(
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
      @typed_spreadsheet.CellResult::TypeError(message) => {
        inspect(message, content="Mul requires Int on the right side")
        true
      }
      _ => false
    },
    content="true",
  )
}

///|
test "typed spreadsheet: formula AST gt rejects non-int terms" {
  let rt = @incr.Runtime()
  let sheet = @typed_spreadsheet.Worksheet(rt, @typed_spreadsheet.SheetId(110))
  let a1 = @typed_spreadsheet.CellId(sheet.sheet_id(), "A1")
  let a2 = @typed_spreadsheet.CellId(sheet.sheet_id(), "A2")
  let b1 = @typed_spreadsheet.CellId(sheet.sheet_id(), "B1")

  inspect(
    sheet.set_input(a1, @typed_spreadsheet.CellValue::from_bool(true)).is_ok(),
    content="true",
  )
  inspect(
    sheet.set_input(a2, @typed_spreadsheet.CellValue::from_int(1)).is_ok(),
    content="true",
  )

  let formula = @typed_spreadsheet.Formula::gt(
    @typed_spreadsheet.Formula::cell_ref(a1),
    @typed_spreadsheet.Formula::cell_ref(a2),
  )
  let _ = sheet.set_formula_ast(
    b1,
    @typed_spreadsheet.CellType::t_bool(),
    formula,
  )

  inspect(
    match sheet.read(b1) {
      @typed_spreadsheet.CellResult::TypeError(message) => {
        inspect(message, content="Gt requires Int on the left side")
        true
      }
      _ => false
    },
    content="true",
  )
}

///|
test "typed spreadsheet: formula AST if rejects non-bool condition" {
  let rt = @incr.Runtime()
  let sheet = @typed_spreadsheet.Worksheet(rt, @typed_spreadsheet.SheetId(111))
  let condition = @typed_spreadsheet.CellId(sheet.sheet_id(), "A1")
  let b1 = @typed_spreadsheet.CellId(sheet.sheet_id(), "B1")

  inspect(
    sheet
    .set_input(condition, @typed_spreadsheet.CellValue::from_int(1))
    .is_ok(),
    content="true",
  )

  let formula = @typed_spreadsheet.Formula::if_(
    @typed_spreadsheet.Formula::cell_ref(condition),
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

  inspect(
    match sheet.read(b1) {
      @typed_spreadsheet.CellResult::TypeError(message) => {
        inspect(message, content="If requires Bool condition")
        true
      }
      _ => false
    },
    content="true",
  )
}

///|
test "typed spreadsheet: formula AST if short-circuits unevaluated branch" {
  let rt = @incr.Runtime()
  let sheet = @typed_spreadsheet.Worksheet(rt, @typed_spreadsheet.SheetId(112))
  let condition = @typed_spreadsheet.CellId(sheet.sheet_id(), "A1")
  let true_value = @typed_spreadsheet.CellId(sheet.sheet_id(), "A2")
  let error_left = @typed_spreadsheet.CellId(sheet.sheet_id(), "A3")
  let b1 = @typed_spreadsheet.CellId(sheet.sheet_id(), "B1")

  inspect(
    sheet
    .set_input(condition, @typed_spreadsheet.CellValue::from_bool(true))
    .is_ok(),
    content="true",
  )
  inspect(
    sheet
    .set_input(true_value, @typed_spreadsheet.CellValue::from_int(10))
    .is_ok(),
    content="true",
  )
  inspect(
    sheet
    .set_input(error_left, @typed_spreadsheet.CellValue::from_text("bad"))
    .is_ok(),
    content="true",
  )

  let formula = @typed_spreadsheet.Formula::if_(
    @typed_spreadsheet.Formula::cell_ref(condition),
    @typed_spreadsheet.Formula::cell_ref(true_value),
    @typed_spreadsheet.Formula::add(
      @typed_spreadsheet.Formula::cell_ref(error_left),
      @typed_spreadsheet.Formula::literal(
        @typed_spreadsheet.CellValue::from_int(1),
      ),
    ),
  )
  let _ = sheet.set_formula_ast(
    b1,
    @typed_spreadsheet.CellType::t_int(),
    formula,
  )

  match sheet.read(b1) {
    @typed_spreadsheet.CellResult::Ok(@typed_spreadsheet.CellValue::Int(value)) =>
      inspect(value, content="10")
    _ => abort("expected true branch result under short-circuit")
  }

  inspect(
    sheet
    .set_input(condition, @typed_spreadsheet.CellValue::from_bool(false))
    .is_ok(),
    content="true",
  )

  inspect(
    sheet
    .set_input(error_left, @typed_spreadsheet.CellValue::from_int(2))
    .is_ok(),
    content="true",
  )

  match sheet.read(b1) {
    @typed_spreadsheet.CellResult::Ok(@typed_spreadsheet.CellValue::Int(value)) =>
      inspect(value, content="3")
    _ => abort("expected else branch result after condition flips")
  }
}

///|
test "typed spreadsheet: formula AST if does not pre-read inactive missing branch" {
  let rt = @incr.Runtime()
  let sheet = @typed_spreadsheet.Worksheet(rt, @typed_spreadsheet.SheetId(113))
  let missing = @typed_spreadsheet.CellId(sheet.sheet_id(), "Z9")
  let b1 = @typed_spreadsheet.CellId(sheet.sheet_id(), "B1")

  let formula = @typed_spreadsheet.Formula::if_(
    @typed_spreadsheet.Formula::literal(
      @typed_spreadsheet.CellValue::from_bool(true),
    ),
    @typed_spreadsheet.Formula::literal(
      @typed_spreadsheet.CellValue::from_int(1),
    ),
    @typed_spreadsheet.Formula::cell_ref(missing),
  )
  let _ = sheet.set_formula_ast(
    b1,
    @typed_spreadsheet.CellType::t_int(),
    formula,
  )

  match sheet.read(b1) {
    @typed_spreadsheet.CellResult::Ok(@typed_spreadsheet.CellValue::Int(value)) =>
      inspect(value, content="1")
    _ =>
      abort("expected true branch value to avoid reading missing false branch")
  }
}

///|
test "typed spreadsheet: formula AST if does not pre-read missing true branch" {
  let rt = @incr.Runtime()
  let sheet = @typed_spreadsheet.Worksheet(rt, @typed_spreadsheet.SheetId(114))
  let missing = @typed_spreadsheet.CellId(sheet.sheet_id(), "Z9")
  let b1 = @typed_spreadsheet.CellId(sheet.sheet_id(), "B1")

  let formula = @typed_spreadsheet.Formula::if_(
    @typed_spreadsheet.Formula::literal(
      @typed_spreadsheet.CellValue::from_bool(false),
    ),
    @typed_spreadsheet.Formula::cell_ref(missing),
    @typed_spreadsheet.Formula::literal(
      @typed_spreadsheet.CellValue::from_int(2),
    ),
  )
  let _ = sheet.set_formula_ast(
    b1,
    @typed_spreadsheet.CellType::t_int(),
    formula,
  )

  match sheet.read(b1) {
    @typed_spreadsheet.CellResult::Ok(@typed_spreadsheet.CellValue::Int(value)) =>
      inspect(value, content="2")
    _ =>
      abort("expected false branch value to avoid reading missing true branch")
  }
}

///|
test "typed spreadsheet: formula AST resolves after missing dependency is created" {
  let rt = @incr.Runtime()
  let sheet = @typed_spreadsheet.Worksheet(rt, @typed_spreadsheet.SheetId(103))
  let missing = @typed_spreadsheet.CellId(sheet.sheet_id(), "Z9")
  let b1 = @typed_spreadsheet.CellId(sheet.sheet_id(), "B1")

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

  inspect(
    sheet.set_input(missing, @typed_spreadsheet.CellValue::from_int(30)).is_ok(),
    content="true",
  )

  match sheet.read(b1) {
    @typed_spreadsheet.CellResult::Ok(@typed_spreadsheet.CellValue::Int(value)) =>
      inspect(value, content="31")
    _ => abort("expected missing dependency to resolve after creation")
  }
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
