///|
test "publish_cell_changes: advances revision, marks changed_at, fires on_change" {
  let rt = Runtime::new()
  let sig = Signal::new(rt, 0)
  let cell_id = sig.id()
  let before = rt.core.current_revision
  let mut fired = false
  rt.set_on_change(() => { fired = true })
  rt.publish_cell_changes([cell_id], Low)
  // Revision advanced
  inspect(rt.core.current_revision > before, content="true")
  // changed_at updated
  inspect(
    rt.core.cell_ops[cell_id.id].changed_at() == rt.core.current_revision,
    content="true",
  )
  // on_change fired
  inspect(fired, content="true")
}

///|
test "panic cross-runtime: get_pull_signal aborts when cell belongs to a different runtime" {
  // Runtime::get_pull_signal aborts with "Cell belongs to a different Runtime"
  // when the CellId's runtime_id does not match the runtime being queried.
  // This guards internal operations that walk the dependency graph: if a
  // cross-runtime CellId ever ended up in a cell's dependency list, the
  // verification walk would abort here rather than silently reading wrong state.
  let rt_a = Runtime::new()
  let rt_b = Runtime::new()
  let sig_b = Signal::new(rt_b, 42)
  // Directly querying rt_a with sig_b's cell_id must abort
  let _ = rt_a.get_pull_signal(sig_b.cell_id)
}
