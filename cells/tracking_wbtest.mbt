///|
test "tracking: begin/end tracking records dependency" {
  let rt = Runtime::new()
  let sig = Signal::new(rt, 42)
  let m = Memo::new(rt, () => 0)
  rt.begin_tracking(m.id())
  let _ = sig.get()
  let deps = rt.end_tracking()
  inspect(deps.length(), content="1")
  inspect(deps[0] == sig.id(), content="true")
}

///|
test "tracking: finish_tracking adds memo to dep subscribers" {
  let rt = Runtime::new()
  let sig = Signal::new(rt, 1)
  let m = Memo::new(rt, () => 0)
  // Exercise finish_tracking directly: begin a tracking frame, read sig to
  // register it as a dependency, end the frame, then call finish_tracking
  // with empty old_deps (first compute) and the captured new_deps.
  rt.begin_tracking(m.id())
  let _ = sig.get()
  let new_deps = rt.end_tracking()
  rt.finish_tracking(m.id(), [], new_deps)
  let sig_idx = match rt.core.cell_index[sig.id().id] {
    PullSignal(i) => i
    _ => abort("expected PullSignal")
  }
  inspect(
    rt.pull.signals[sig_idx].meta.subscribers.contains(m.id()),
    content="true",
  )
}

///|
test "get_subscribers: returns empty iter for new signal" {
  let rt = Runtime::new()
  let sig = Signal::new(rt, 1)
  let count = rt.get_subscribers(sig.id()).fold(init=0, fn(acc, _) { acc + 1 })
  inspect(count, content="0")
}

///|
test "get_subscribers: contains memo after first get" {
  let rt = Runtime::new()
  let sig = Signal::new(rt, 1)
  let m = Memo::new(rt, () => sig.get())
  let _ = rt.read(m)
  let subs : Array[CellId] = []
  for sub in rt.get_subscribers(sig.id()) {
    subs.push(sub)
  }
  inspect(subs.length(), content="1")
  inspect(subs[0] == m.id(), content="true")
}
