///|
test "panic cross-runtime: get_cell aborts when cell belongs to a different runtime" {
  // Runtime::get_cell aborts with "Cell belongs to a different Runtime" when
  // the CellId's runtime_id does not match the runtime being queried.
  // This guards internal operations that walk the dependency graph: if a
  // cross-runtime CellId ever ended up in a cell's dependency list, the
  // verification walk would abort here rather than silently reading wrong state.
  let rt_a = Runtime::new()
  let rt_b = Runtime::new()
  let sig_b = Signal::new(rt_b, 42)
  // Directly querying rt_a with sig_b's cell_id must abort
  let _ = rt_a.get_cell(sig_b.cell_id)
}
