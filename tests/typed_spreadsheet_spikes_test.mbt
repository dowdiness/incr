///|
suberror SpreadsheetBatchError {
  Abort
}

///|
test "typed spreadsheet spike: batch rollback removes newly created cells" {
  let rt = @incr.Runtime()
  let sheet = @typed_spreadsheet.Worksheet(rt, @typed_spreadsheet.SheetId(200))
  let source = @typed_spreadsheet.CellId(sheet.sheet_id(), "A1")
  let formula = @typed_spreadsheet.CellId(sheet.sheet_id(), "B1")
  let formula_ast = @typed_spreadsheet.CellId(sheet.sheet_id(), "C1")

  inspect(
    sheet.set_input(source, @typed_spreadsheet.CellValue::from_int(1)).is_ok(),
    content="true",
  )

  let result = rt.batch_result(() => {
    let _ = sheet.set_input(
      @typed_spreadsheet.CellId(sheet.sheet_id(), "D1"),
      @typed_spreadsheet.CellValue::from_int(2),
    )
    let _ = sheet.set_formula(
      formula,
      @typed_spreadsheet.CellType::t_int(),
      [],
      fn(_deps) {
        @typed_spreadsheet.CellResult::ok(
          @typed_spreadsheet.CellValue::from_int(10),
        )
      },
    )
    let first = @typed_spreadsheet.Formula::literal(
      @typed_spreadsheet.CellValue::from_int(20),
    )
    let _ = sheet.set_formula_ast(
      formula_ast,
      @typed_spreadsheet.CellType::t_int(),
      first,
    )
    raise SpreadsheetBatchError::Abort
  })

  inspect(result is Err(Abort), content="true")

  inspect(
    match sheet.read(@typed_spreadsheet.CellId(sheet.sheet_id(), "D1")) {
      @typed_spreadsheet.CellResult::RefError(_) => true
      _ => false
    },
    content="true",
  )
  inspect(
    match sheet.read(formula) {
      @typed_spreadsheet.CellResult::RefError(_) => true
      _ => false
    },
    content="true",
  )
  inspect(
    match sheet.read(formula_ast) {
      @typed_spreadsheet.CellResult::RefError(_) => true
      _ => false
    },
    content="true",
  )
}

///|
test "typed spreadsheet spike: batch rollback restores deleted cells" {
  let rt = @incr.Runtime()
  let sheet = @typed_spreadsheet.Worksheet(rt, @typed_spreadsheet.SheetId(201))
  let source = @typed_spreadsheet.CellId(sheet.sheet_id(), "A1")

  inspect(
    sheet.set_input(source, @typed_spreadsheet.CellValue::from_int(7)).is_ok(),
    content="true",
  )

  let result = rt.batch_result(() => {
    let _ = sheet.delete(source)
    raise SpreadsheetBatchError::Abort
  })

  inspect(result is Err(Abort), content="true")
  match sheet.read(source) {
    @typed_spreadsheet.CellResult::Ok(@typed_spreadsheet.CellValue::Int(value)) =>
      inspect(value, content="7")
    _ => abort("expected source to survive batch rollback")
  }
}

///|
test "typed spreadsheet spike: batch_result rollback on raised error" {
  let rt = @incr.Runtime()
  let source = @incr.InputField(rt, 1, label="source")
  let modifier = @incr.Input(rt, 2, label="modifier")
  let total = @incr.Derived(rt, () => source.get() + modifier.get())
  inspect(total.read_or_abort(), content="3")

  let mut global_calls = 0
  rt.set_on_change(() => global_calls = global_calls + 1)

  let result = rt.batch_result(() => {
    source.set(10)
    modifier.set(20)
    raise SpreadsheetBatchError::Abort
  })

  inspect(result is Err(Abort), content="true")
  inspect(source.get(), content="1")
  inspect(modifier.get(), content="2")
  inspect(total.read_or_abort(), content="3")
  inspect(global_calls, content="0")
}

///|
test "typed spreadsheet spike: same-value set is callback-silent" {
  let rt = @incr.Runtime()
  let source = @incr.InputField(rt, 5, label="source")
  let mut global_calls = 0
  let mut field_calls = 0
  let mut derived_runs = 0

  rt.set_on_change(() => global_calls = global_calls + 1)
  source.on_change(_ => field_calls = field_calls + 1)
  let derived = @incr.Derived(rt, () => {
    derived_runs = derived_runs + 1
    source.get() + 1
  })

  inspect(derived.read_or_abort(), content="6")
  inspect(derived_runs, content="1")
  inspect(global_calls, content="0")
  inspect(field_calls, content="0")

  // Same-value updates should be a no-op end-to-end.
  source.set(5)
  inspect(global_calls, content="0")
  inspect(field_calls, content="0")
  inspect(derived_runs, content="1")

  source.set(6)
  inspect(derived.read_or_abort(), content="7")
  inspect(derived_runs, content="2")
  inspect(global_calls, content="1")
  inspect(field_calls, content="1")
}

///|
test "typed spreadsheet spike: on_memo_event tracks formula chain recompute" {
  let rt = @incr.Runtime()
  let source = @incr.Input(rt, 1, label="source")
  let step_a = @incr.Derived(rt, () => source.get() + 1)
  let step_b = @incr.Derived(rt, () => step_a.read_or_abort() * 2)
  let watch = step_b.watch()

  let entering : Array[@incr.CellId] = []
  let completed : Array[@incr.CellId] = []
  rt.on_memo_event(fn(evt) {
    match evt {
      EnteringCompute(e) => entering.push(e.cell_id)
      Completed(e) => completed.push(e.cell_id)
      Aborted(_) => ()
    }
  })

  inspect(watch.read_or_abort(), content="4")
  entering.clear()
  completed.clear()

  source.set(2)
  inspect(watch.read_or_abort(), content="6")

  inspect(entering.length(), content="2")
  inspect(entering.contains(step_a.id()), content="true")
  inspect(entering.contains(step_b.id()), content="true")
  inspect(completed.length(), content="2")
  inspect(completed.contains(step_a.id()), content="true")
  inspect(completed.contains(step_b.id()), content="true")

  watch.dispose()
}

///|
test "typed spreadsheet spike: cell_info tracks revision and deps" {
  let rt = @incr.Runtime()
  let scope = @incr.Scope::new(rt)
  let source = scope.signal(10, label="source")
  let derived = scope.derived(() => source.get() / 2)

  let _ = derived.read_or_abort()

  match rt.cell_info(derived.id()) {
    Some(before) => {
      let before_changed = before.changed_at.value
      let before_verified = before.verified_at.value
      inspect(before.dependencies.contains(source.id()), content="true")

      source.set_unconditional(10)
      inspect(derived.read_or_abort(), content="5")

      match rt.cell_info(derived.id()) {
        Some(after) => {
          inspect(after.changed_at.value == before_changed, content="true")
          inspect(after.verified_at.value > before_verified, content="true")
          inspect(after.dependencies.contains(source.id()), content="true")
        }
        None => abort("expected derived CellInfo after update")
      }
    }
    None => abort("expected derived CellInfo before update")
  }

  scope.dispose()
}

///|
test "typed spreadsheet spike: scope disposal isolates worksheet" {
  let rt = @incr.Runtime()
  let sheet = @incr.Scope::new(rt)
  let toolbar = @incr.Scope::new(rt)

  let sheet_input = sheet.input_field(1, label="sheet_input")
  let sheet_sum = sheet.derived(() => sheet_input.get() + 1, label="sheet_sum")
  let toolbar_input = toolbar.input_field(100, label="toolbar_input")
  let toolbar_delta = toolbar.derived(
    () => toolbar_input.get() + 2,
    label="toolbar_delta",
  )

  inspect(sheet_sum.read_or_abort(), content="2")
  inspect(toolbar_delta.read_or_abort(), content="102")

  sheet.dispose()

  inspect(sheet_input.is_disposed(), content="true")
  inspect(sheet_sum.is_disposed(), content="true")
  inspect(toolbar_input.is_disposed(), content="false")
  inspect(toolbar_delta.is_disposed(), content="false")
  inspect(toolbar_delta.read_or_abort(), content="102")

  toolbar.dispose()
  inspect(toolbar_input.is_disposed(), content="true")
  inspect(toolbar_delta.is_disposed(), content="true")
}

///|
test "typed spreadsheet spike: set_on_change + Watch for formula/reactive chains" {
  let rt = @incr.Runtime()
  let source = @incr.Input(rt, 3, label="source")
  let formula = @incr.Derived(rt, () => source.get() + 1)
  let reactive = @incr.EagerDerived(rt, fn() { source.get() * 2 })
  let formula_watch = formula.watch()
  let reactive_watch = reactive.watch()

  let mut global_calls = 0
  rt.set_on_change(() => global_calls = global_calls + 1)

  inspect(formula_watch.read_or_abort(), content="4")
  inspect(reactive_watch.read_or_abort(), content="6")

  source.set(4)
  inspect(formula_watch.read_or_abort(), content="5")
  inspect(reactive_watch.read_or_abort(), content="8")
  inspect(global_calls, content="1")

  formula_watch.dispose()
  reactive_watch.dispose()
}
