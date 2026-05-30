///|
test "typed spreadsheet demo parser: integer input text becomes SetInput" {
  let target = cell("A1")

  match parse_cell_text_op(target, " 10 ") {
    Ok(SetInput(id, Int(value))) => {
      inspect(id == target, content="true")
      inspect(value, content="10")
    }
    _ => abort("expected SetInput Int(10)")
  }
}

///|
test "typed spreadsheet demo parser: cell reference formula text becomes Formula::cell_ref" {
  let target = cell("B1")
  let source = cell("A1")

  match parse_cell_text_op(target, "=A1") {
    Ok(SetFormulaAst(id, TInt, Ref(ref_id))) => {
      inspect(id == target, content="true")
      inspect(ref_id == source, content="true")
    }
    _ => abort("expected SetFormulaAst TInt Ref(A1)")
  }
}

///|
test "typed spreadsheet demo parser: addition formula text becomes Formula::add" {
  let target = cell("B1")
  let source = cell("A1")

  match parse_cell_text_op(target, "=A1 + 1") {
    Ok(SetFormulaAst(id, TInt, Add(Ref(ref_id), Literal(Int(value))))) => {
      inspect(id == target, content="true")
      inspect(ref_id == source, content="true")
      inspect(value, content="1")
    }
    _ => abort("expected SetFormulaAst TInt Add(A1, 1)")
  }
}

///|
test "typed spreadsheet demo parser: multiplication formula text becomes Formula::mul" {
  let target = cell("B1")
  let source = cell("A1")

  match parse_cell_text_op(target, "=A1*2") {
    Ok(SetFormulaAst(id, TInt, Mul(Ref(ref_id), Literal(Int(value))))) => {
      inspect(id == target, content="true")
      inspect(ref_id == source, content="true")
      inspect(value, content="2")
    }
    _ => abort("expected SetFormulaAst TInt Mul(A1, 2)")
  }
}

///|
test "typed spreadsheet demo parser: conditional formula text becomes Formula::if_" {
  let target = cell("B1")
  let source = cell("A1")

  match parse_cell_text_op(target, "=if(A1 > 10, 1, 0)") {
    Ok(
      SetFormulaAst(
        id,
        TInt,
        If(
          Gt(Ref(ref_id), Literal(Int(threshold))),
          Literal(Int(then_value)),
          Literal(Int(else_value))
        )
      )
    ) => {
      inspect(id == target, content="true")
      inspect(ref_id == source, content="true")
      inspect(threshold, content="10")
      inspect(then_value, content="1")
      inspect(else_value, content="0")
    }
    _ => abort("expected SetFormulaAst TInt if(A1 > 10, 1, 0)")
  }
}

///|
test "typed spreadsheet demo parser: parsed formula runs through operation runner" {
  let sheet = new_sheet(20)
  let a1 = @typed_spreadsheet.CellId(sheet.sheet_id(), "A1")
  let b1 = @typed_spreadsheet.CellId(sheet.sheet_id(), "B1")
  ignore(sheet.set_input(a1, @typed_spreadsheet.CellValue::from_int(10)))
  let op = match parse_cell_text_op(b1, "=A1 + 1") {
    Ok(value) => value
    Err(_) => abort("expected formula parse to succeed")
  }

  let result = run_op(sheet, op)

  match result.outcome {
    SetFormulaAst(Ok(_)) => inspect(true, content="true")
    _ => abort("expected SetFormulaAst Ok outcome")
  }
  let formula_change = result.cell_snapshots[0]
  inspect(formula_change.after.static_references.contains(a1), content="true")
  match formula_change.after.result {
    Ok(Int(value)) => inspect(value, content="11")
    _ => abort("expected parsed formula to evaluate to Int(11)")
  }
}

///|
test "typed spreadsheet demo parser: parse errors are Result values" {
  match parse_cell_text_op(cell("A1"), " ") {
    Err(EmptyInput) => inspect(true, content="true")
    _ => abort("expected EmptyInput error")
  }
  match parse_cell_text_op(cell("A1"), "abc") {
    Err(InvalidInteger("abc")) => inspect(true, content="true")
    _ => abort("expected InvalidInteger error")
  }
  match parse_cell_text_op(cell("A1"), "=A1 - 1") {
    Err(UnsupportedFormula("A1 - 1")) => inspect(true, content="true")
    _ => abort("expected UnsupportedFormula error")
  }
}

///|
fn cell(address : String) -> @typed_spreadsheet.CellId {
  @typed_spreadsheet.CellId(@typed_spreadsheet.SheetId(99), address)
}
