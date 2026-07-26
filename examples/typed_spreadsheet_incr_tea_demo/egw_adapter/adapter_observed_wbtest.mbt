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
test "adapter observed remote apply captures target dependent and trace" {
  let (source, _) = fixture_start("observed-remote-source", 34)
  let (target, _) = attach_peer(source, "observed-remote-target", 34)
  let baseline = source.version()
  ignore(command(source, "A1", "20"))
  let observed = try! target.apply_sync_observed(
    source.export_since(baseline),
    capture_limit=16,
    trace_cells=[id(target, "A1"), id(target, "B1")],
  )
  assert_true(
    observed.result().adapter_result() is AdapterApplyResult::Applied(_),
  )
  assert_true(observed.targets().contains(id(target, "A1")))
  assert_eq(observed.snapshots().length(), 2)
  assert_true(observed.trace().changed().contains(id(target, "B1")))
  inspect(
    @demo.format_cell_result(observed.snapshots()[0].before().result()),
    content="Ok(Int(10))",
  )
  inspect(
    @demo.format_cell_result(observed.snapshots()[0].after().result()),
    content="Ok(Int(20))",
  )
  source.dispose()
  target.dispose()
}

///|
test "adapter observed remote evidence clamps caller capture limit" {
  let (source, _) = fixture_start("observed-limit-source", 35)
  let (target, _) = attach_peer(source, "observed-limit-target", 35)
  let baseline = source.version()
  let cells = @domain.grid_cells()
  let addresses = cells[0:20]
  let trace_cells = []
  addresses.eachi((index, address) => {
    ignore(command(source, address, "\{index + 1}"))
    trace_cells.push(id(target, address))
  })
  let observed = try! target.apply_sync_observed(
    source.export_since(baseline),
    capture_limit=99,
    trace_cells~,
  )
  assert_eq(observed.targets().length(), 16)
  assert_eq(observed.snapshots().length(), 16)
  source.dispose()
  target.dispose()
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
