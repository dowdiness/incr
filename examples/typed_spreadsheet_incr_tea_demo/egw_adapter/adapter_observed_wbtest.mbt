///|
test "adapter observed apply owns trace and before-after evidence" {
  let (adapter, _) = fixture_start("observed-replica", 31)
  let target = id(adapter, "A1")
  let observed = try! adapter.apply_command_observed(
    @domain.SheetCommand::ApplyFromSelection(target, "15", adapter.generation()),
    @domain.SheetExecutionContext::SheetExecutionContext(
      target,
      None,
      adapter.generation(),
    ),
    capture=[target],
    trace_cells=[target, id(adapter, "B1")],
  )
  assert_true(observed.target() == Some(target))
  assert_eq(observed.snapshots().length(), 1)
  inspect(
    @demo.format_cell_result(observed.snapshots()[0].before().result()),
    content="Ok(Int(10))",
  )
  inspect(
    @demo.format_cell_result(observed.snapshots()[0].after().result()),
    content="Ok(Int(15))",
  )
  match observed.result() {
    AdapterApplyResult::Applied(_) => ()
    _ => fail("expected applied observed result")
  }
  match observed.trace() {
    Some(trace) => assert_true(trace.changed().contains(id(adapter, "B1")))
    None => fail("expected observed trace")
  }
  adapter.dispose()
}

///|
test "adapter formula_ast wrapper reads projected formula" {
  let (adapter, _) = fixture_start("formula-replica", 32)
  match adapter.formula_ast("B1") {
    Ok(_) => ()
    Err(error) => fail("expected formula AST: \{repr(error)}")
  }
  adapter.dispose()
}

///|
test "adapter dispose is safe at the authority boundary" {
  let (adapter, _) = fixture_start("dispose-replica", 33)
  adapter.dispose()
  adapter.dispose()
}
