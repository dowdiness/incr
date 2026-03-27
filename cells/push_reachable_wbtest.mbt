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
