///|
test "cell_ops: signal has ops at its id index" {
  let rt = Runtime::new()
  let sig = Signal::new(rt, 42)
  inspect(rt.core.cell_ops.length(), content="1")
  let ops = rt.core.cell_ops[sig.id().id]
  inspect(ops.cell_id() == sig.id(), content="true")
  inspect(ops.label(), content="None")
}

///|
test "cell_ops: memo has ops at its id index" {
  let rt = Runtime::new()
  let m = Memo::new(rt, () => 0)
  inspect(rt.core.cell_ops.length(), content="1")
  let ops = rt.core.cell_ops[m.id().id]
  inspect(ops.cell_id() == m.id(), content="true")
}

///|
test "cell_ops: set_changed_at mutates the SoA struct" {
  let rt = Runtime::new()
  let sig = Signal::new(rt, 1)
  let ops = rt.core.cell_ops[sig.id().id]
  let rev1 = Revision::next(Revision::initial())
  ops.set_changed_at(rev1)
  inspect(rt.get_changed_at(sig.id()) == rev1, content="true")
}

///|
test "cell_ops: signal and memo ids are distinct when both exist" {
  let rt = Runtime::new()
  let sig = Signal::new(rt, 1)
  let m = Memo::new(rt, () => sig.get())
  inspect(rt.core.cell_ops.length(), content="2")
  inspect(rt.core.cell_ops[sig.id().id].cell_id() == sig.id(), content="true")
  inspect(rt.core.cell_ops[m.id().id].cell_id() == m.id(), content="true")
}
