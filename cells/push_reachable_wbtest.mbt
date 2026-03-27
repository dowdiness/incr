///|
test "push_reachable_count: new signal starts at 0" {
  let rt = Runtime::new()
  let s = Signal::new(rt, 0)
  let idx = match rt.core.cell_index[s.id().id] {
    PullSignal(i) => i
    _ => abort("expected PullSignal")
  }
  inspect(rt.pull.signals[idx].meta.push_reachable_count, content="0")
}

///|
test "collect_reachable_cells: signal returns {signal}" {
  let rt = Runtime::new()
  let s = Signal::new(rt, 0)
  let cells = rt.collect_reachable_cells([s.id()])
  inspect(cells.contains(s.id()), content="true")
  inspect(cells.length(), content="1")
}

///|
test "collect_reachable_cells: memo returns memo + upstream signal" {
  let rt = Runtime::new()
  let s = Signal::new(rt, 0)
  let m = Memo::new(rt, () => s.get())
  ignore(m.get()) // force compute so dependencies are recorded
  let cells = rt.collect_reachable_cells([m.id()])
  inspect(cells.contains(m.id()), content="true")
  inspect(cells.contains(s.id()), content="true")
  inspect(cells.length(), content="2")
}

///|
test "collect_reachable_cells: uncomputed memo returns only memo" {
  let rt = Runtime::new()
  let s = Signal::new(rt, 0)
  let m = Memo::new(rt, () => s.get())
  // m.get() NOT called — dependencies array is empty
  let cells = rt.collect_reachable_cells([m.id()])
  inspect(cells.contains(m.id()), content="true")
  inspect(cells.length(), content="1")
}

///|
test "push_contribution: reactive returns 1" {
  let rt = Runtime::new()
  let s = Signal::new(rt, 0)
  let r = Reactive::new(rt, () => s.get())
  inspect(rt.push_contribution(r.id()), content="1")
}

///|
test "push_contribution: signal returns 0" {
  let rt = Runtime::new()
  let s = Signal::new(rt, 0)
  inspect(rt.push_contribution(s.id()), content="0")
}
