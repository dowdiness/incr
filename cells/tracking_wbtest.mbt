///|
test "tracking: begin/end tracking records dependency" {
  let rt = Runtime::new()
  let sig = Signal::new(rt, 42)
  let memo_id = rt.alloc_cell_id(CellRef::PullMemo(0))
  rt.begin_tracking(memo_id)
  let _ = sig.get()
  let deps = rt.end_tracking()
  inspect(deps.length(), content="1")
  inspect(deps[0] == sig.id(), content="true")
}

///|
test "tracking: finish_tracking adds memo to dep subscribers" {
  let rt = Runtime::new()
  let sig = Signal::new(rt, 1)
  let m = Memo::new(rt, () => sig.get())
  let _ = m.get()
  // After get, finish_tracking should have added m to sig's subscribers
  let sig_idx = match rt.cell_index[sig.id().id] {
    PullSignal(i) => i
    _ => abort("expected PullSignal")
  }
  inspect(rt.pull_signals[sig_idx].subscribers.contains(m.id()), content="true")
}

///|
test "get_subscribers: returns empty iter for new signal" {
  let rt = Runtime::new()
  let sig = Signal::new(rt, 1)
  let count = rt.get_subscribers(rt.cell_index[sig.id().id]).fold(
    init=0,
    fn(acc, _) { acc + 1 },
  )
  inspect(count, content="0")
}

///|
test "get_subscribers: contains memo after first get" {
  let rt = Runtime::new()
  let sig = Signal::new(rt, 1)
  let m = Memo::new(rt, () => sig.get())
  let _ = m.get()
  let subs : Array[CellId] = []
  for sub in rt.get_subscribers(rt.cell_index[sig.id().id]) {
    subs.push(sub)
  }
  inspect(subs.length(), content="1")
  inspect(subs[0] == m.id(), content="true")
}
