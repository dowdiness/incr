///|
test "tracking: begin/end tracking records dependency" {
  let rt = Runtime::Runtime()
  let sig = Input::Input(rt, 42)
  let m = Derived(rt, () => 0)
  rt.begin_tracking(m.id())
  let _ = sig.get()
  let (deps, _seen) = rt.end_tracking()
  inspect(deps.length(), content="1")
  inspect(deps[0] == sig.id(), content="true")
}

///|
test "tracking: finish_tracking adds memo to dep subscribers" {
  let rt = Runtime::Runtime()
  let sig = Input::Input(rt, 1)
  let m = Derived(rt, () => 0)
  // Exercise finish_tracking directly: begin a tracking frame, read sig to
  // register it as a dependency, end the frame, then call finish_tracking
  // with empty old_deps (first compute) and the captured new_deps.
  rt.begin_tracking(m.id())
  let _ = sig.get()
  let (new_deps, new_seen) = rt.end_tracking()
  rt.finish_tracking(m.id(), [], new_deps, new_seen)
  let sig_idx = match rt.core.cell_index[sig.id().id] {
    PullInput(i) => i
    _ => abort("expected PullInput")
  }
  inspect(
    rt.pull.inputs[sig_idx].meta.subscribers.contains(m.id()),
    content="true",
  )
}

///|
test "get_subscribers: returns empty iter for new input" {
  let rt = Runtime::Runtime()
  let sig = Input::Input(rt, 1)
  let count = rt.get_subscribers(sig.id()).fold(init=0, fn(acc, _) { acc + 1 })
  inspect(count, content="0")
}

///|
test "get_subscribers: contains memo after first get" {
  let rt = Runtime::Runtime()
  let sig = Input::Input(rt, 1)
  let m = Derived(rt, () => sig.get())
  let _ = m.read_or_abort()
  let subs : Array[CellId] = []
  for sub in rt.get_subscribers(sig.id()) {
    subs.push(sub)
  }
  inspect(subs.length(), content="1")
  inspect(subs[0] == m.id(), content="true")
}
