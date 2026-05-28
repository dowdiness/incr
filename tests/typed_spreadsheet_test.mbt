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
  let _ = sheet.set_formula(
    sum,
    @typed_spreadsheet.CellType::t_int(),
    [a1, a2],
    fn(deps) {
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
          @typed_spreadsheet.CellResult::type_error(
            "formula dependency mismatch",
          )
      }
    },
  )

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
test "typed spreadsheet: inspect input snapshot" {
  let rt = @incr.Runtime()
  let sheet = @typed_spreadsheet.Worksheet(rt, @typed_spreadsheet.SheetId(2))
  let cell = @typed_spreadsheet.CellId(sheet.sheet_id(), "A1")

  inspect(
    sheet.set_input(cell, @typed_spreadsheet.CellValue::from_int(10)).is_ok(),
    content="true",
  )

  let snapshot = sheet.inspect_cell(cell)
  inspect(snapshot.id == cell, content="true")
  inspect(snapshot.present, content="true")
  match snapshot.kind {
    Some(_) => inspect(true, content="true")
    None => inspect(false, content="false")
  }
  inspect(snapshot.installed_dependencies.length(), content="0")
  inspect(snapshot.static_references.length(), content="0")

  match snapshot.result {
    @typed_spreadsheet.CellResult::Ok(@typed_spreadsheet.CellValue::Int(value)) =>
      inspect(value, content="10")
    _ => abort("expected Ok(Int(10)) for input snapshot")
  }
}

///|
test "typed spreadsheet: inspect formula snapshot" {
  let rt = @incr.Runtime()
  let sheet = @typed_spreadsheet.Worksheet(rt, @typed_spreadsheet.SheetId(3))
  let a1 = @typed_spreadsheet.CellId(sheet.sheet_id(), "A1")
  let a2 = @typed_spreadsheet.CellId(sheet.sheet_id(), "A2")
  let target = @typed_spreadsheet.CellId(sheet.sheet_id(), "B1")

  inspect(
    sheet.set_input(a1, @typed_spreadsheet.CellValue::from_int(10)).is_ok(),
    content="true",
  )
  inspect(
    sheet.set_input(a2, @typed_spreadsheet.CellValue::from_int(20)).is_ok(),
    content="true",
  )
  let _ = sheet.set_formula(
    target,
    @typed_spreadsheet.CellType::t_int(),
    [a1, a2],
    fn(deps) {
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
          @typed_spreadsheet.CellResult::type_error(
            "formula dependency mismatch",
          )
      }
    },
  )

  let snapshot = sheet.inspect_cell(target)
  inspect(snapshot.present, content="true")
  inspect(snapshot.installed_dependencies.length(), content="2")
  inspect(snapshot.installed_dependencies[0] == a1, content="true")
  inspect(snapshot.installed_dependencies[1] == a2, content="true")
  inspect(snapshot.static_references.length(), content="2")
  inspect(snapshot.static_references[0] == a1, content="true")
  inspect(snapshot.static_references[1] == a2, content="true")
  match snapshot.kind {
    Some(_) => inspect(true, content="true")
    None => inspect(false, content="false")
  }

  match snapshot.result {
    @typed_spreadsheet.CellResult::Ok(@typed_spreadsheet.CellValue::Int(value)) =>
      inspect(value, content="30")
    _ => abort("expected formula snapshot result to be Ok(Int(30))")
  }
}

///|
test "typed spreadsheet: trace captures recompute and change" {
  let rt = @incr.Runtime()
  let sheet = @typed_spreadsheet.Worksheet(rt, @typed_spreadsheet.SheetId(4))
  let a1 = @typed_spreadsheet.CellId(sheet.sheet_id(), "A1")
  let a2 = @typed_spreadsheet.CellId(sheet.sheet_id(), "A2")
  let target = @typed_spreadsheet.CellId(sheet.sheet_id(), "B1")

  inspect(
    sheet.set_input(a1, @typed_spreadsheet.CellValue::from_int(10)).is_ok(),
    content="true",
  )
  inspect(
    sheet.set_input(a2, @typed_spreadsheet.CellValue::from_int(20)).is_ok(),
    content="true",
  )
  let _ = sheet.set_formula(
    target,
    @typed_spreadsheet.CellType::t_int(),
    [a1, a2],
    fn(deps) {
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
          @typed_spreadsheet.CellResult::type_error(
            "formula dependency mismatch",
          )
      }
    },
  )

  // Prime baseline state so dependency change is observable.
  match sheet.read(target) {
    @typed_spreadsheet.CellResult::Ok(_) => ()
    _ => abort("expected formula to evaluate initially")
  }

  let (_, trace) = sheet.trace(fn() {
    let _ = sheet.set_input(a1, @typed_spreadsheet.CellValue::from_int(11))
    ()
  })

  inspect(trace.recomputed.contains(target), content="true")
  inspect(trace.changed.contains(target), content="true")
  inspect(trace.unchanged.length(), content="0")
  inspect(trace.changed.length(), content="1")
}

///|
test "typed spreadsheet: trace captures unchanged recompute" {
  let rt = @incr.Runtime()
  let sheet = @typed_spreadsheet.Worksheet(rt, @typed_spreadsheet.SheetId(5))
  let a1 = @typed_spreadsheet.CellId(sheet.sheet_id(), "A1")
  let target = @typed_spreadsheet.CellId(sheet.sheet_id(), "B1")

  inspect(
    sheet.set_input(a1, @typed_spreadsheet.CellValue::from_int(7)).is_ok(),
    content="true",
  )
  let _ = sheet.set_formula(
    target,
    @typed_spreadsheet.CellType::t_int(),
    [a1],
    fn(deps) {
      match deps[0] {
        @typed_spreadsheet.CellValue::Int(value) =>
          @typed_spreadsheet.CellResult::ok(
            @typed_spreadsheet.CellValue::from_int(value + 1 - 1 + 0),
          )
        _ =>
          @typed_spreadsheet.CellResult::type_error(
            "formula dependency mismatch",
          )
      }
    },
  )

  match sheet.read(target) {
    @typed_spreadsheet.CellResult::Ok(_) => ()
    _ => abort("expected formula to evaluate initially")
  }

  let (_, trace) = sheet.trace(fn() {
    let _ = sheet.set_input(a1, @typed_spreadsheet.CellValue::from_int(7))
    ()
  })

  inspect(trace.recomputed.contains(target), content="true")
  inspect(trace.changed.contains(target), content="false")
  inspect(trace.unchanged.contains(target), content="true")
}

///|
test "typed spreadsheet: trace includes newly created formulas" {
  let rt = @incr.Runtime()
  let sheet = @typed_spreadsheet.Worksheet(rt, @typed_spreadsheet.SheetId(6))
  let input = @typed_spreadsheet.CellId(sheet.sheet_id(), "A1")
  let formula = @typed_spreadsheet.CellId(sheet.sheet_id(), "B1")

  inspect(
    sheet.set_input(input, @typed_spreadsheet.CellValue::from_int(3)).is_ok(),
    content="true",
  )

  let (_, trace) = sheet.trace(fn() {
    let _ = sheet.set_formula(
      formula,
      @typed_spreadsheet.CellType::t_int(),
      [input],
      fn(deps) {
        match deps[0] {
          @typed_spreadsheet.CellValue::Int(value) =>
            @typed_spreadsheet.CellResult::ok(
              @typed_spreadsheet.CellValue::from_int(value * 2),
            )
          _ =>
            @typed_spreadsheet.CellResult::type_error(
              "formula dependency mismatch",
            )
        }
      },
    )
    ()
  })

  inspect(trace.recomputed.contains(formula), content="true")
  inspect(trace.changed.contains(formula), content="true")
}

///|
test "typed spreadsheet: inspect missing snapshot" {
  let rt = @incr.Runtime()
  let sheet = @typed_spreadsheet.Worksheet(rt, @typed_spreadsheet.SheetId(4))
  let missing = @typed_spreadsheet.CellId(sheet.sheet_id(), "Z9")

  let snapshot = sheet.inspect_cell(missing)
  inspect(snapshot.present, content="false")
  match snapshot.kind {
    Some(_) => inspect(false, content="false")
    None => inspect(true, content="true")
  }

  match snapshot.result {
    @typed_spreadsheet.CellResult::RefError(_) => inspect(true, content="true")
    _ => abort("expected missing snapshot to report RefError")
  }
}

///|
test "typed spreadsheet: inspect deleted snapshot" {
  let rt = @incr.Runtime()
  let sheet = @typed_spreadsheet.Worksheet(rt, @typed_spreadsheet.SheetId(5))
  let cell = @typed_spreadsheet.CellId(sheet.sheet_id(), "A1")

  inspect(
    sheet.set_input(cell, @typed_spreadsheet.CellValue::from_int(1)).is_ok(),
    content="true",
  )

  let before = sheet.inspect_cell(cell)
  inspect(before.present, content="true")

  inspect(sheet.delete(cell).is_ok(), content="true")

  let after = sheet.inspect_cell(cell)
  inspect(after.present, content="false")
  match after.result {
    @typed_spreadsheet.CellResult::RefError(_) => inspect(true, content="true")
    _ => abort("expected deleted snapshot to report RefError")
  }
}

///|
test "typed spreadsheet: inspect formula AST snapshot refs" {
  let rt = @incr.Runtime()
  let sheet = @typed_spreadsheet.Worksheet(rt, @typed_spreadsheet.SheetId(6))
  let a1 = @typed_spreadsheet.CellId(sheet.sheet_id(), "A1")
  let a2 = @typed_spreadsheet.CellId(sheet.sheet_id(), "A2")
  let target = @typed_spreadsheet.CellId(sheet.sheet_id(), "B1")

  inspect(
    sheet.set_input(a1, @typed_spreadsheet.CellValue::from_int(2)).is_ok(),
    content="true",
  )
  inspect(
    sheet.set_input(a2, @typed_spreadsheet.CellValue::from_int(3)).is_ok(),
    content="true",
  )

  let formula = @typed_spreadsheet.Formula::add(
    @typed_spreadsheet.Formula::cell_ref(a1),
    @typed_spreadsheet.Formula::add(
      @typed_spreadsheet.Formula::cell_ref(a2),
      @typed_spreadsheet.Formula::literal(
        @typed_spreadsheet.CellValue::from_int(1),
      ),
    ),
  )

  let _ = sheet.set_formula_ast(
    target,
    @typed_spreadsheet.CellType::t_int(),
    formula,
  )

  let snapshot = sheet.inspect_cell(target)
  inspect(snapshot.installed_dependencies.length(), content="0")
  inspect(snapshot.static_references.length(), content="2")
  inspect(snapshot.static_references[0] == a1, content="true")
  inspect(snapshot.static_references[1] == a2, content="true")

  match snapshot.result {
    @typed_spreadsheet.CellResult::Ok(@typed_spreadsheet.CellValue::Int(value)) =>
      inspect(value, content="6")
    _ => abort("expected AST snapshot result to be Ok(Int(6))")
  }
}

///|
test "typed spreadsheet: inspect AST snapshot keeps static refs for inactive branches" {
  let rt = @incr.Runtime()
  let sheet = @typed_spreadsheet.Worksheet(rt, @typed_spreadsheet.SheetId(60))
  let condition = @typed_spreadsheet.CellId(sheet.sheet_id(), "A1")
  let inactive = @typed_spreadsheet.CellId(sheet.sheet_id(), "B9")
  let target = @typed_spreadsheet.CellId(sheet.sheet_id(), "C1")

  inspect(
    sheet
    .set_input(condition, @typed_spreadsheet.CellValue::from_bool(true))
    .is_ok(),
    content="true",
  )

  let formula = @typed_spreadsheet.Formula::if_(
    @typed_spreadsheet.Formula::cell_ref(condition),
    @typed_spreadsheet.Formula::literal(
      @typed_spreadsheet.CellValue::from_int(1),
    ),
    @typed_spreadsheet.Formula::add(
      @typed_spreadsheet.Formula::cell_ref(inactive),
      @typed_spreadsheet.Formula::literal(
        @typed_spreadsheet.CellValue::from_int(99),
      ),
    ),
  )

  let _ = sheet.set_formula_ast(
    target,
    @typed_spreadsheet.CellType::t_int(),
    formula,
  )

  let snapshot = sheet.inspect_cell(target)
  inspect(snapshot.installed_dependencies.length(), content="0")
  inspect(snapshot.static_references.length(), content="2")
  inspect(snapshot.static_references[0] == condition, content="true")
  inspect(snapshot.static_references[1] == inactive, content="true")

  match sheet.read(target) {
    @typed_spreadsheet.CellResult::Ok(@typed_spreadsheet.CellValue::Int(value)) =>
      inspect(value, content="1")
    _ =>
      abort(
        "expected inactive branch to be skipped and return true-branch value",
      )
  }
}

///|
test "typed spreadsheet: inspect cross-sheet cell is RefError" {
  let rt = @incr.Runtime()
  let sheet = @typed_spreadsheet.Worksheet(rt, @typed_spreadsheet.SheetId(7))
  let foreign = @typed_spreadsheet.Worksheet(
    @incr.Runtime(),
    @typed_spreadsheet.SheetId(70),
  )
  let foreign_cell = @typed_spreadsheet.CellId(foreign.sheet_id(), "A1")

  let snapshot = sheet.inspect_cell(foreign_cell)
  inspect(snapshot.present, content="false")

  match snapshot.result {
    @typed_spreadsheet.CellResult::RefError(_) => inspect(true, content="true")
    _ => abort("expected cross-sheet inspect snapshot to return RefError")
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
  let _ = sheet.set_formula(
    b1,
    @typed_spreadsheet.CellType::t_int(),
    [a1, a2],
    fn(deps) {
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
          @typed_spreadsheet.CellResult::type_error(
            "formula dependency mismatch",
          )
      }
    },
  )

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
  let _ = sheet.set_formula(
    b1,
    @typed_spreadsheet.CellType::t_int(),
    [missing],
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

  inspect(
    match sheet.read(b1) {
      @typed_spreadsheet.CellResult::RefError(_) => true
      _ => false
    },
    content="true",
  )

  inspect(
    sheet.set_input(missing, @typed_spreadsheet.CellValue::from_int(10)).is_ok(),
    content="true",
  )

  match sheet.read(b1) {
    @typed_spreadsheet.CellResult::Ok(@typed_spreadsheet.CellValue::Int(value)) =>
      inspect(value, content="11")
    _ => abort("expected missing reference to resolve after input appears")
  }
}

///|
test "typed spreadsheet: set_formula preserves dependency TypeError" {
  let rt = @incr.Runtime()
  let sheet = @typed_spreadsheet.Worksheet(rt, @typed_spreadsheet.SheetId(12))
  let a1 = @typed_spreadsheet.CellId(sheet.sheet_id(), "A1")
  let b1 = @typed_spreadsheet.CellId(sheet.sheet_id(), "B1")

  let _ = sheet.set_formula(a1, @typed_spreadsheet.CellType::t_int(), [], fn(
    _deps,
  ) {
    @typed_spreadsheet.CellResult::type_error("dependency failed")
  })

  let _ = sheet.set_formula(b1, @typed_spreadsheet.CellType::t_int(), [a1], fn(
    deps,
  ) {
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
  let _ = sheet.set_formula(b1, @typed_spreadsheet.CellType::t_int(), deps, fn(
    deps,
  ) {
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
test "typed spreadsheet: overwrite input invalidates dependent formula" {
  let rt = @incr.Runtime()
  let sheet = @typed_spreadsheet.Worksheet(rt, @typed_spreadsheet.SheetId(200))
  let b1 = @typed_spreadsheet.CellId(sheet.sheet_id(), "B1")
  let a1 = @typed_spreadsheet.CellId(sheet.sheet_id(), "A1")

  inspect(
    sheet.set_input(b1, @typed_spreadsheet.CellValue::from_int(1)).is_ok(),
    content="true",
  )
  let _ = sheet.set_formula(a1, @typed_spreadsheet.CellType::t_int(), [b1], fn(
    deps,
  ) {
    match deps[0] {
      @typed_spreadsheet.CellValue::Int(value) =>
        @typed_spreadsheet.CellResult::ok(
          @typed_spreadsheet.CellValue::from_int(value + 1),
        )
      _ => @typed_spreadsheet.CellResult::type_error("bad value")
    }
  })

  match sheet.read(a1) {
    @typed_spreadsheet.CellResult::Ok(@typed_spreadsheet.CellValue::Int(total)) =>
      inspect(total, content="2")
    _ => abort("expected Ok(Int(2)) before overwrite")
  }

  inspect(
    sheet.set_input(b1, @typed_spreadsheet.CellValue::from_int(10)).is_ok(),
    content="true",
  )

  match sheet.read(a1) {
    @typed_spreadsheet.CellResult::Ok(@typed_spreadsheet.CellValue::Int(total)) =>
      inspect(total, content="11")
    _ => abort("expected Ok(Int(11)) after input overwrite")
  }
}

///|
test "typed spreadsheet: overwrite formula invalidates dependent formula" {
  let rt = @incr.Runtime()
  let sheet = @typed_spreadsheet.Worksheet(rt, @typed_spreadsheet.SheetId(201))
  let b1 = @typed_spreadsheet.CellId(sheet.sheet_id(), "B1")
  let a1 = @typed_spreadsheet.CellId(sheet.sheet_id(), "A1")

  inspect(
    sheet.set_input(b1, @typed_spreadsheet.CellValue::from_int(1)).is_ok(),
    content="true",
  )
  let _ = sheet.set_formula(a1, @typed_spreadsheet.CellType::t_int(), [b1], fn(
    deps,
  ) {
    match deps[0] {
      @typed_spreadsheet.CellValue::Int(value) =>
        @typed_spreadsheet.CellResult::ok(
          @typed_spreadsheet.CellValue::from_int(value + 1),
        )
      _ => @typed_spreadsheet.CellResult::type_error("bad value")
    }
  })

  inspect(
    match
      sheet.set_formula(b1, @typed_spreadsheet.CellType::t_int(), [], fn(
        _deps,
      ) {
        @typed_spreadsheet.CellResult::ok(
          @typed_spreadsheet.CellValue::from_int(20),
        )
      }) {
      Ok(_) => true
      _ => false
    },
    content="true",
  )

  match sheet.read(a1) {
    @typed_spreadsheet.CellResult::Ok(@typed_spreadsheet.CellValue::Int(total)) =>
      inspect(total, content="21")
    _ => abort("expected Ok(Int(21)) after formula overwrite")
  }
}

///|
test "typed spreadsheet: dependent formula follows formula replacement" {
  let rt = @incr.Runtime()
  let sheet = @typed_spreadsheet.Worksheet(rt, @typed_spreadsheet.SheetId(202))
  let b1 = @typed_spreadsheet.CellId(sheet.sheet_id(), "B1")
  let a1 = @typed_spreadsheet.CellId(sheet.sheet_id(), "A1")

  inspect(
    match
      sheet.set_formula(b1, @typed_spreadsheet.CellType::t_int(), [], fn(
        _deps,
      ) {
        @typed_spreadsheet.CellResult::ok(
          @typed_spreadsheet.CellValue::from_int(2),
        )
      }) {
      Ok(_) => true
      _ => false
    },
    content="true",
  )
  let _ = sheet.set_formula(a1, @typed_spreadsheet.CellType::t_int(), [b1], fn(
    deps,
  ) {
    match deps[0] {
      @typed_spreadsheet.CellValue::Int(value) =>
        @typed_spreadsheet.CellResult::ok(
          @typed_spreadsheet.CellValue::from_int(value + 1),
        )
      _ => @typed_spreadsheet.CellResult::type_error("bad value")
    }
  })

  inspect(
    sheet.set_input(b1, @typed_spreadsheet.CellValue::from_int(10)).is_ok(),
    content="true",
  )

  match sheet.read(a1) {
    @typed_spreadsheet.CellResult::Ok(@typed_spreadsheet.CellValue::Int(total)) =>
      inspect(total, content="11")
    _ => abort("expected Ok(Int(11)) after formula→input overwrite")
  }
}

///|
test "typed spreadsheet: dependency error on overwrite/delete propagates downstream" {
  let rt = @incr.Runtime()
  let sheet = @typed_spreadsheet.Worksheet(rt, @typed_spreadsheet.SheetId(203))
  let b1 = @typed_spreadsheet.CellId(sheet.sheet_id(), "B1")
  let a1 = @typed_spreadsheet.CellId(sheet.sheet_id(), "A1")

  inspect(
    sheet.set_input(b1, @typed_spreadsheet.CellValue::from_int(1)).is_ok(),
    content="true",
  )
  let _ = sheet.set_formula(a1, @typed_spreadsheet.CellType::t_int(), [b1], fn(
    deps,
  ) {
    match deps[0] {
      @typed_spreadsheet.CellValue::Int(value) =>
        @typed_spreadsheet.CellResult::ok(
          @typed_spreadsheet.CellValue::from_int(value + 1),
        )
      _ => @typed_spreadsheet.CellResult::type_error("bad value")
    }
  })

  match sheet.delete(b1) {
    @typed_spreadsheet.CellResult::Ok(_) => ()
    _ => abort("delete should remove B1")
  }

  inspect(
    match sheet.read(a1) {
      @typed_spreadsheet.CellResult::RefError(_) => true
      _ => false
    },
    content="true",
  )
}

///|
test "typed spreadsheet: delete invalidates cached dependent formula" {
  let rt = @incr.Runtime()
  let sheet = @typed_spreadsheet.Worksheet(rt, @typed_spreadsheet.SheetId(204))
  let b1 = @typed_spreadsheet.CellId(sheet.sheet_id(), "B1")
  let a1 = @typed_spreadsheet.CellId(sheet.sheet_id(), "A1")

  inspect(
    sheet.set_input(b1, @typed_spreadsheet.CellValue::from_int(10)).is_ok(),
    content="true",
  )
  let _ = sheet.set_formula(a1, @typed_spreadsheet.CellType::t_int(), [b1], fn(
    deps,
  ) {
    match deps[0] {
      @typed_spreadsheet.CellValue::Int(value) =>
        @typed_spreadsheet.CellResult::ok(
          @typed_spreadsheet.CellValue::from_int(value + 1),
        )
      _ => @typed_spreadsheet.CellResult::type_error("dependency mismatch")
    }
  })

  match sheet.read(a1) {
    @typed_spreadsheet.CellResult::Ok(@typed_spreadsheet.CellValue::Int(total)) =>
      inspect(total, content="11")
    _ => abort("expected cached formula result before delete")
  }

  match sheet.delete(b1) {
    @typed_spreadsheet.CellResult::Ok(_) => ()
    _ => abort("delete should remove B1")
  }

  match sheet.read(a1) {
    @typed_spreadsheet.CellResult::RefError(_) => ()
    _ => abort("expected dependent formula to become RefError after delete")
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
test "typed spreadsheet: rejected overwrite keeps deleted cell absent" {
  let rt = @incr.Runtime()
  let sheet = @typed_spreadsheet.Worksheet(rt, @typed_spreadsheet.SheetId(6))
  let cell = @typed_spreadsheet.CellId(sheet.sheet_id(), "A1")

  inspect(
    sheet.set_input(cell, @typed_spreadsheet.CellValue::from_int(42)).is_ok(),
    content="true",
  )

  inspect(sheet.delete(cell).is_ok(), content="true")

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

  inspect(
    match sheet.read(cell) {
      @typed_spreadsheet.CellResult::RefError(_) => true
      _ => false
    },
    content="true",
  )

  inspect(
    sheet.set_input(cell, @typed_spreadsheet.CellValue::from_int(43)).is_ok(),
    content="true",
  )

  match sheet.read(cell) {
    @typed_spreadsheet.CellResult::Ok(@typed_spreadsheet.CellValue::Int(value)) =>
      inspect(value, content="43")
    _ => abort("expected restored Int after valid overwrite")
  }
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
  let _ = sheet.set_formula(
    dependent,
    @typed_spreadsheet.CellType::t_int(),
    [target],
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

  match sheet.read(dependent) {
    @typed_spreadsheet.CellResult::Ok(@typed_spreadsheet.CellValue::Int(total)) =>
      inspect(total, content="3")
    _ => abort("expected initial dependent result")
  }

  let _ = sheet.set_formula(
    target,
    @typed_spreadsheet.CellType::t_int(),
    [source],
    fn(deps) {
      match deps[0] {
        @typed_spreadsheet.CellValue::Int(value) =>
          @typed_spreadsheet.CellResult::ok(
            @typed_spreadsheet.CellValue::from_int(value + 10),
          )
        _ =>
          @typed_spreadsheet.CellResult::type_error(
            "formula dependency mismatch",
          )
      }
    },
  )

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

///|
test "typed spreadsheet: cross-sheet read is rejected" {
  let rt = @incr.Runtime()
  let sheet = @typed_spreadsheet.Worksheet(rt, @typed_spreadsheet.SheetId(7))
  let foreign = @typed_spreadsheet.CellId(@typed_spreadsheet.SheetId(8), "A1")

  inspect(
    match sheet.read(foreign) {
      @typed_spreadsheet.CellResult::RefError(_) => true
      _ => false
    },
    content="true",
  )
}

///|
test "typed spreadsheet: cross-sheet operations return RefError" {
  let rt = @incr.Runtime()
  let sheet = @typed_spreadsheet.Worksheet(rt, @typed_spreadsheet.SheetId(14))
  let same_sheet = @typed_spreadsheet.CellId(sheet.sheet_id(), "A1")
  let foreign = @typed_spreadsheet.CellId(@typed_spreadsheet.SheetId(15), "A1")

  inspect(
    match sheet.set_input(foreign, @typed_spreadsheet.CellValue::from_int(1)) {
      @typed_spreadsheet.CellResult::RefError(_) => true
      _ => false
    },
    content="true",
  )

  inspect(
    match sheet.delete(foreign) {
      @typed_spreadsheet.CellResult::RefError(_) => true
      _ => false
    },
    content="true",
  )

  inspect(
    sheet
    .set_input(same_sheet, @typed_spreadsheet.CellValue::from_int(2))
    .is_ok(),
    content="true",
  )
  inspect(
    match sheet.read(same_sheet) {
      @typed_spreadsheet.CellResult::Ok(_) => true
      _ => false
    },
    content="true",
  )
}

///|
test "typed spreadsheet: set_formula blocks foreign references" {
  let rt = @incr.Runtime()
  let sheet = @typed_spreadsheet.Worksheet(rt, @typed_spreadsheet.SheetId(16))
  let local_target = @typed_spreadsheet.CellId(sheet.sheet_id(), "B1")
  let foreign = @typed_spreadsheet.CellId(@typed_spreadsheet.SheetId(17), "A1")

  let _ = sheet.set_input(
    local_target,
    @typed_spreadsheet.CellValue::from_int(10),
  )

  inspect(
    match
      sheet.set_formula(foreign, @typed_spreadsheet.CellType::t_int(), [], fn(
        _deps,
      ) {
        @typed_spreadsheet.CellResult::ok(
          @typed_spreadsheet.CellValue::from_int(1),
        )
      }) {
      Err(@typed_spreadsheet.WorksheetError::RefError(_)) => true
      _ => false
    },
    content="true",
  )

  inspect(
    match
      sheet.set_formula(
        local_target,
        @typed_spreadsheet.CellType::t_int(),
        [foreign],
        fn(_deps) {
          @typed_spreadsheet.CellResult::ok(
            @typed_spreadsheet.CellValue::from_int(1),
          )
        },
      ) {
      Err(@typed_spreadsheet.WorksheetError::RefError(_)) => true
      _ => false
    },
    content="true",
  )

  inspect(
    match
      sheet.set_formula_ast(
        local_target,
        @typed_spreadsheet.CellType::t_int(),
        @typed_spreadsheet.Formula::add(
          @typed_spreadsheet.Formula::cell_ref(foreign),
          @typed_spreadsheet.Formula::literal(
            @typed_spreadsheet.CellValue::from_int(1),
          ),
        ),
      ) {
      Err(@typed_spreadsheet.WorksheetError::RefError(_)) => true
      _ => false
    },
    content="true",
  )

  match sheet.read(local_target) {
    @typed_spreadsheet.CellResult::Ok(@typed_spreadsheet.CellValue::Int(value)) =>
      inspect(value, content="10")
    _ => abort("expected local cell value to remain intact")
  }
}
