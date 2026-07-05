///|
test "get_changed_at: dispatches via cell_index" {
  let rt = Runtime::Runtime()
  let sig = Input::Input(rt, 1)
  let rev = rt.get_changed_at(sig.id())
  inspect(rev >= Revision::initial(), content="true")
}

///|
test "cell_id_for: round-trips through cell_index" {
  let rt = Runtime::Runtime()
  let sig = Input::Input(rt, 1)
  let cell_id = @kernel.cell_id_for(
    rt.pull,
    rt.push,
    rt.datalog,
    rt.core.cell_index[sig.id().id],
  )
  inspect(cell_id == sig.id(), content="true")
}

///|
test "runtime: SoA fields exist and start empty" {
  let rt = Runtime::Runtime()
  inspect(rt.pull.inputs.length(), content="0")
  inspect(rt.pull.memos.length(), content="0")
  inspect(rt.core.cell_index.length(), content="0")
}

///|
test "Input::Input: allocates into pull_inputs" {
  let rt = Runtime::Runtime()
  let sig = Input::Input(rt, 42)
  inspect(rt.pull.inputs.length(), content="1")
  match rt.core.cell_index[sig.id().id] {
    PullInput(i) => inspect(i, content="0")
    _ => abort("expected PullInput")
  }
}

///|
test "Memo::Memo: allocates into pull_memos" {
  let rt = Runtime::Runtime()
  let sig = Input::Input(rt, 1)
  let m = Derived(rt, () => sig.get())
  let _ = m.read_or_abort()
  inspect(rt.pull.memos.length(), content="1")
  match rt.core.cell_index[m.id().id] {
    PullMemo(i) => inspect(i, content="0")
    _ => abort("expected PullMemo")
  }
}

///|
test "runtime: dispatch tables stay index-aligned across all cell kinds" {
  // Pins the invariant that install_cell (and, for memo/hybrid, their
  // local equivalents) pushes cell_index, cell_ops, and cell_lifecycle
  // together. This is load-bearing for dispatch by cell_id.id.
  let rt = Runtime::Runtime()
  rt.check_table_invariant()
  let sig = Input::Input(rt, 1)
  rt.check_table_invariant()
  let m = Derived(rt, () => sig.get())
  let _ = m.read_or_abort()
  rt.check_table_invariant()
  let hm = ReachableDerived(rt, () => sig.get())
  let _ = hm.read_or_abort()
  rt.check_table_invariant()
  let r = EagerDerived::EagerDerived(rt, () => sig.get())
  rt.check_table_invariant()
  let _ = Effect::Effect(rt, () => sig.get() |> ignore)
  rt.check_table_invariant()
  // Disposal updates slots in place (cell_index[i] -> Disposed); lengths
  // are unchanged, so the invariant still holds.
  sig.dispose()
  r.dispose()
  rt.check_table_invariant()
}

///|
test "runtime: alloc_cell_id populates cell_index" {
  // This test exercises alloc_cell_id in isolation. alloc_cell_id only grows
  // cell_index; it does not populate rt.pull.inputs. The transient
  // inconsistency (cell_index[0] pointing to PullInput(0) while
  // rt.pull.inputs is empty) is intentional — we are testing the low-level
  // allocation primitive, not the full Runtime invariants.
  let rt = Runtime::Runtime()
  let cell_id = rt.alloc_cell_id(CellRef::PullInput(0))
  inspect(cell_id.id, content="0")
  inspect(rt.core.cell_index.length(), content="1")
  match rt.core.cell_index[0] {
    PullInput(i) => inspect(i, content="0")
    _ => abort("expected PullInput")
  }
}
