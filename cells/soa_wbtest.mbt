///|
test "runtime: SoA fields exist and start empty" {
  let rt = Runtime::new()
  inspect(rt.pull_signals.length(), content="0")
  inspect(rt.pull_memos.length(), content="0")
  inspect(rt.cell_index.length(), content="0")
}

///|
test "new_signal_id: allocates into pull_signals" {
  let rt = Runtime::new()
  let sig = Signal::new(rt, 42)
  inspect(rt.pull_signals.length(), content="1")
  match rt.cell_index[sig.id().id] {
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
  inspect(rt.pull_memos.length(), content="1")
  match rt.cell_index[m.id().id] {
    PullMemo(i) => inspect(i, content="0")
    _ => abort("expected PullMemo")
  }
}

///|
test "runtime: alloc_cell_id populates cell_index" {
  let rt = Runtime::new()
  let cell_id = rt.alloc_cell_id(CellRef::PullSignal(0))
  inspect(cell_id.id, content="0")
  inspect(rt.cell_index.length(), content="1")
  match rt.cell_index[0] {
    PullSignal(i) => inspect(i, content="0")
    _ => abort("expected PullSignal")
  }
}
