///|
test "get_changed_at: dispatches via cell_index" {
  let rt = Runtime::new()
  let sig = Signal::new(rt, 1)
  let rev = rt.get_changed_at(sig.id())
  inspect(rev >= Revision::initial(), content="true")
}

///|
test "cell_id_for: round-trips through cell_index" {
  let rt = Runtime::new()
  let sig = Signal::new(rt, 1)
  let cell_id = rt.cell_id_for(rt.core.cell_index[sig.id().id])
  inspect(cell_id == sig.id(), content="true")
}

///|
test "runtime: SoA fields exist and start empty" {
  let rt = Runtime::new()
  inspect(rt.pull.signals.length(), content="0")
  inspect(rt.pull.memos.length(), content="0")
  inspect(rt.core.cell_index.length(), content="0")
}

///|
test "new_signal_id: allocates into pull_signals" {
  let rt = Runtime::new()
  let sig = Signal::new(rt, 42)
  inspect(rt.pull.signals.length(), content="1")
  match rt.core.cell_index[sig.id().id] {
    PullSignal(i) => inspect(i, content="0")
    _ => abort("expected PullSignal")
  }
}

///|
test "new_memo_id: allocates into pull_memos" {
  let rt = Runtime::new()
  let sig = Signal::new(rt, 1)
  let m = Memo::new(rt, () => sig.get())
  let _ = m.get()
  inspect(rt.pull.memos.length(), content="1")
  match rt.core.cell_index[m.id().id] {
    PullMemo(i) => inspect(i, content="0")
    _ => abort("expected PullMemo")
  }
}

///|
test "runtime: alloc_cell_id populates cell_index" {
  // This test exercises alloc_cell_id in isolation. alloc_cell_id only grows
  // cell_index; it does not populate rt.pull.signals. The transient
  // inconsistency (cell_index[0] pointing to PullSignal(0) while
  // rt.pull.signals is empty) is intentional — we are testing the low-level
  // allocation primitive, not the full Runtime invariants.
  let rt = Runtime::new()
  let cell_id = rt.alloc_cell_id(CellRef::PullSignal(0))
  inspect(cell_id.id, content="0")
  inspect(rt.core.cell_index.length(), content="1")
  match rt.core.cell_index[0] {
    PullSignal(i) => inspect(i, content="0")
    _ => abort("expected PullSignal")
  }
}
