///|
/// Tests for the typed spreadsheet boundary package.

///|
test "typed spreadsheet: input and formula basics" {
  let rt = @incr.Runtime()
  let sheet = @typed_spreadsheet.Worksheet(rt, @typed_spreadsheet.SheetId(1))
  let a1 = @typed_spreadsheet.CellId(sheet.sheet_id(), "A1")
  let a2 = @typed_spreadsheet.CellId(sheet.sheet_id(), "A2")
  let sum = @typed_spreadsheet.CellId(sheet.sheet_id(), "B1")

  inspect(
    sheet.set_input(a1, @typed_spreadsheet.CellValue::from_int(10)).is_ok(),
    content="true",
  )
  inspect(
    sheet.set_input(a2, @typed_spreadsheet.CellValue::from_int(20)).is_ok(),
    content="true",
  )
  sheet.set_formula(sum, @typed_spreadsheet.CellType::t_int(), [a1, a2], fn(
    deps,
  ) {
    match deps[0] {
      @typed_spreadsheet.CellValue::Int(lhs) =>
        match deps[1] {
          @typed_spreadsheet.CellValue::Int(rhs) =>
            @typed_spreadsheet.CellResult::ok(
              @typed_spreadsheet.CellValue::from_int(lhs + rhs),
            )
          _ =>
            @typed_spreadsheet.CellResult::type_error(
              "formula dependency mismatch",
            )
        }
      _ =>
        @typed_spreadsheet.CellResult::type_error("formula dependency mismatch")
    }
  })

  match sheet.read(sum) {
    @typed_spreadsheet.CellResult::Ok(@typed_spreadsheet.CellValue::Int(total)) =>
      inspect(total, content="30")
    _ => abort("expected Ok(Int) from typed spreadsheet formula")
  }

  inspect(
    sheet.set_input(a1, @typed_spreadsheet.CellValue::from_int(11)).is_ok(),
    content="true",
  )
  match sheet.read(sum) {
    @typed_spreadsheet.CellResult::Ok(@typed_spreadsheet.CellValue::Int(total)) =>
      inspect(total, content="31")
    _ => abort("expected Ok(Int) after input update")
  }
}

///|
test "typed spreadsheet: set_formula type error is propagated" {
  let rt = @incr.Runtime()
  let sheet = @typed_spreadsheet.Worksheet(rt, @typed_spreadsheet.SheetId(10))
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
  sheet.set_formula(b1, @typed_spreadsheet.CellType::t_int(), [a1, a2], fn(
    deps,
  ) {
    match deps[0] {
      @typed_spreadsheet.CellValue::Int(lhs) =>
        match deps[1] {
          @typed_spreadsheet.CellValue::Int(rhs) =>
            @typed_spreadsheet.CellResult::ok(
              @typed_spreadsheet.CellValue::from_int(lhs + rhs),
            )
          _ =>
            @typed_spreadsheet.CellResult::type_error(
              "formula dependency mismatch",
            )
        }
      _ =>
        @typed_spreadsheet.CellResult::type_error("formula dependency mismatch")
    }
  })

  inspect(
    match sheet.read(b1) {
      @typed_spreadsheet.CellResult::TypeError(message) =>
        message == "formula dependency mismatch"
      _ => false
    },
    content="true",
  )
}

///|
test "typed spreadsheet: set_formula undefined reference is RefError" {
  let rt = @incr.Runtime()
  let sheet = @typed_spreadsheet.Worksheet(rt, @typed_spreadsheet.SheetId(11))
  let a1 = @typed_spreadsheet.CellId(sheet.sheet_id(), "A1")
  let b1 = @typed_spreadsheet.CellId(sheet.sheet_id(), "B1")

  inspect(
    sheet.set_input(a1, @typed_spreadsheet.CellValue::from_int(20)).is_ok(),
    content="true",
  )

  let missing = @typed_spreadsheet.CellId(sheet.sheet_id(), "Z9")
  sheet.set_formula(b1, @typed_spreadsheet.CellType::t_int(), [missing], fn(
    deps,
  ) {
    match deps[0] {
      @typed_spreadsheet.CellValue::Int(value) =>
        @typed_spreadsheet.CellResult::ok(
          @typed_spreadsheet.CellValue::from_int(value + 1),
        )
      _ =>
        @typed_spreadsheet.CellResult::type_error("formula dependency mismatch")
    }
  })

  inspect(
    match sheet.read(b1) {
      @typed_spreadsheet.CellResult::RefError(_) => true
      _ => false
    },
    content="true",
  )
}

///|
test "typed spreadsheet: set_formula preserves dependency TypeError" {
  let rt = @incr.Runtime()
  let sheet = @typed_spreadsheet.Worksheet(rt, @typed_spreadsheet.SheetId(12))
  let a1 = @typed_spreadsheet.CellId(sheet.sheet_id(), "A1")
  let b1 = @typed_spreadsheet.CellId(sheet.sheet_id(), "B1")

  sheet.set_formula(a1, @typed_spreadsheet.CellType::t_int(), [], fn(_deps) {
    @typed_spreadsheet.CellResult::type_error("dependency failed")
  })

  sheet.set_formula(b1, @typed_spreadsheet.CellType::t_int(), [a1], fn(deps) {
    match deps[0] {
      @typed_spreadsheet.CellValue::Int(value) =>
        @typed_spreadsheet.CellResult::ok(
          @typed_spreadsheet.CellValue::from_int(value + 1),
        )
      _ => @typed_spreadsheet.CellResult::type_error("bad value")
    }
  })

  inspect(
    match sheet.read(b1) {
      @typed_spreadsheet.CellResult::TypeError(message) =>
        message == "dependency failed"
      _ => false
    },
    content="true",
  )
}

///|
test "typed spreadsheet: set_formula copies dependency array for safety" {
  let rt = @incr.Runtime()
  let sheet = @typed_spreadsheet.Worksheet(rt, @typed_spreadsheet.SheetId(13))
  let a1 = @typed_spreadsheet.CellId(sheet.sheet_id(), "A1")
  let a2 = @typed_spreadsheet.CellId(sheet.sheet_id(), "A2")
  let b1 = @typed_spreadsheet.CellId(sheet.sheet_id(), "B1")

  inspect(
    sheet.set_input(a1, @typed_spreadsheet.CellValue::from_int(5)).is_ok(),
    content="true",
  )

  let deps = [a1]
  sheet.set_formula(b1, @typed_spreadsheet.CellType::t_int(), deps, fn(deps) {
    if deps.length() != 1 {
      @typed_spreadsheet.CellResult::parse_error(
        "dependency set unexpectedly changed",
      )
    } else {
      match deps[0] {
        @typed_spreadsheet.CellValue::Int(value) =>
          @typed_spreadsheet.CellResult::ok(
            @typed_spreadsheet.CellValue::from_int(value * 3),
          )
        _ => @typed_spreadsheet.CellResult::type_error("bad value")
      }
    }
  })

  deps.push(a2)

  match sheet.read(b1) {
    @typed_spreadsheet.CellResult::Ok(@typed_spreadsheet.CellValue::Int(value)) =>
      inspect(value, content="15")
    _ => abort("expected parse-safe formula to keep dependency list stable")
  }
}

///|
test "typed spreadsheet: declared type mismatch is rejected" {
  let rt = @incr.Runtime()
  let sheet = @typed_spreadsheet.Worksheet(rt, @typed_spreadsheet.SheetId(2))
  let cell = @typed_spreadsheet.CellId(sheet.sheet_id(), "A1")

  inspect(
    sheet
    .set_input(
      cell,
      @typed_spreadsheet.CellValue::from_text("bad"),
      declared=@typed_spreadsheet.CellType::t_int(),
    )
    .is_ok(),
    content="false",
  )
}

///|
test "typed spreadsheet: delete disposes the wrapped cell" {
  let rt = @incr.Runtime()
  let sheet = @typed_spreadsheet.Worksheet(rt, @typed_spreadsheet.SheetId(3))
  let cell = @typed_spreadsheet.CellId(sheet.sheet_id(), "A1")

  inspect(
    sheet.set_input(cell, @typed_spreadsheet.CellValue::from_int(1)).is_ok(),
    content="true",
  )
  inspect(sheet.delete(cell).is_ok(), content="true")
  inspect(sheet.read(cell).is_ok(), content="false")
}

///|
test "typed spreadsheet: overwrite formula with input replaces formula cell" {
  let rt = @incr.Runtime()
  let sheet = @typed_spreadsheet.Worksheet(rt, @typed_spreadsheet.SheetId(4))
  let source = @typed_spreadsheet.CellId(sheet.sheet_id(), "A1")
  let target = @typed_spreadsheet.CellId(sheet.sheet_id(), "B1")

  inspect(
    sheet.set_input(source, @typed_spreadsheet.CellValue::from_int(1)).is_ok(),
    content="true",
  )

  let _ = sheet.set_formula(
    target,
    @typed_spreadsheet.CellType::t_int(),
    [source],
    fn(deps) {
      match deps[0] {
        @typed_spreadsheet.CellValue::Int(value) =>
          @typed_spreadsheet.CellResult::ok(
            @typed_spreadsheet.CellValue::from_int(value + 1),
          )
        _ =>
          @typed_spreadsheet.CellResult::type_error(
            "formula dependency mismatch",
          )
      }
    },
  )

  match sheet.read(target) {
    @typed_spreadsheet.CellResult::Ok(@typed_spreadsheet.CellValue::Int(total)) =>
      inspect(total, content="2")
    _ => abort("expected formula result before overwrite")
  }

  inspect(
    sheet.set_input(target, @typed_spreadsheet.CellValue::from_int(100)).is_ok(),
    content="true",
  )
  inspect(
    sheet.set_input(source, @typed_spreadsheet.CellValue::from_int(2)).is_ok(),
    content="true",
  )

  match sheet.read(target) {
    @typed_spreadsheet.CellResult::Ok(@typed_spreadsheet.CellValue::Int(total)) =>
      inspect(total, content="100")
    _ => abort("expected input value after formula overwrite")
  }
}

///|
test "typed spreadsheet: overwrite input with formula updates dependency reads" {
  let rt = @incr.Runtime()
  let sheet = @typed_spreadsheet.Worksheet(rt, @typed_spreadsheet.SheetId(5))
  let source = @typed_spreadsheet.CellId(sheet.sheet_id(), "A1")
  let target = @typed_spreadsheet.CellId(sheet.sheet_id(), "B1")

  inspect(
    sheet.set_input(target, @typed_spreadsheet.CellValue::from_int(10)).is_ok(),
    content="true",
  )
  inspect(
    sheet.set_input(source, @typed_spreadsheet.CellValue::from_int(1)).is_ok(),
    content="true",
  )

  let _ = sheet.set_formula(
    target,
    @typed_spreadsheet.CellType::t_int(),
    [source],
    fn(deps) {
      match deps[0] {
        @typed_spreadsheet.CellValue::Int(value) =>
          @typed_spreadsheet.CellResult::ok(
            @typed_spreadsheet.CellValue::from_int(value * 3),
          )
        _ =>
          @typed_spreadsheet.CellResult::type_error(
            "formula dependency mismatch",
          )
      }
    },
  )

  inspect(
    sheet.set_input(source, @typed_spreadsheet.CellValue::from_int(2)).is_ok(),
    content="true",
  )
  match sheet.read(target) {
    @typed_spreadsheet.CellResult::Ok(@typed_spreadsheet.CellValue::Int(total)) =>
      inspect(total, content="6")
    _ => abort("expected formula result after input->formula overwrite")
  }
}

///|
test "typed spreadsheet: overwrite formula keeps downstream dependencies fresh" {
  let rt = @incr.Runtime()
  let sheet = @typed_spreadsheet.Worksheet(rt, @typed_spreadsheet.SheetId(7))
  let source = @typed_spreadsheet.CellId(sheet.sheet_id(), "A1")
  let target = @typed_spreadsheet.CellId(sheet.sheet_id(), "B1")
  let dependent = @typed_spreadsheet.CellId(sheet.sheet_id(), "C1")

  inspect(
    sheet.set_input(source, @typed_spreadsheet.CellValue::from_int(1)).is_ok(),
    content="true",
  )
  sheet.set_formula(target, @typed_spreadsheet.CellType::t_int(), [source], fn(
    deps,
  ) {
    match deps[0] {
      @typed_spreadsheet.CellValue::Int(value) =>
        @typed_spreadsheet.CellResult::ok(
          @typed_spreadsheet.CellValue::from_int(value + 1),
        )
      _ =>
        @typed_spreadsheet.CellResult::type_error("formula dependency mismatch")
    }
  })
  sheet.set_formula(dependent, @typed_spreadsheet.CellType::t_int(), [target], fn(
    deps,
  ) {
    match deps[0] {
      @typed_spreadsheet.CellValue::Int(value) =>
        @typed_spreadsheet.CellResult::ok(
          @typed_spreadsheet.CellValue::from_int(value + 1),
        )
      _ =>
        @typed_spreadsheet.CellResult::type_error("formula dependency mismatch")
    }
  })

  match sheet.read(dependent) {
    @typed_spreadsheet.CellResult::Ok(@typed_spreadsheet.CellValue::Int(total)) =>
      inspect(total, content="3")
    _ => abort("expected initial dependent result")
  }

  sheet.set_formula(target, @typed_spreadsheet.CellType::t_int(), [source], fn(
    deps,
  ) {
    match deps[0] {
      @typed_spreadsheet.CellValue::Int(value) =>
        @typed_spreadsheet.CellResult::ok(
          @typed_spreadsheet.CellValue::from_int(value + 10),
        )
      _ =>
        @typed_spreadsheet.CellResult::type_error("formula dependency mismatch")
    }
  })

  match sheet.read(dependent) {
    @typed_spreadsheet.CellResult::Ok(@typed_spreadsheet.CellValue::Int(total)) =>
      inspect(total, content="12")
    _ => abort("expected dependent result after formula overwrite")
  }

  inspect(
    sheet.set_input(source, @typed_spreadsheet.CellValue::from_int(2)).is_ok(),
    content="true",
  )

  match sheet.read(dependent) {
    @typed_spreadsheet.CellResult::Ok(@typed_spreadsheet.CellValue::Int(total)) =>
      inspect(total, content="13")
    _ => abort("expected dependent result after source mutation")
  }
}

///|
test "typed spreadsheet: deleting missing cell returns RefError" {
  let rt = @incr.Runtime()
  let sheet = @typed_spreadsheet.Worksheet(rt, @typed_spreadsheet.SheetId(6))
  let missing = @typed_spreadsheet.CellId(sheet.sheet_id(), "Z99")

  inspect(sheet.delete(missing).is_ok(), content="false")
}
