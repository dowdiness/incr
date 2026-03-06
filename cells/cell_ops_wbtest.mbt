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
test "cell_ops: signal level defaults to 0" {
  let rt = Runtime::new()
  let sig = Signal::new(rt, 42)
  let ops = rt.core.cell_ops[sig.id().id]
  inspect(ops.level(), content="0")
}

///|
test "cell_ops: signal dep_changed_since returns Some" {
  let rt = Runtime::new()
  let sig = Signal::new(rt, 1)
  let ops = rt.core.cell_ops[sig.id().id]
  // Signal at initial revision, verified_at = initial → not changed
  inspect(ops.dep_changed_since(Revision::initial()), content="Some(false)")
  // After set, changed_at advances → changed since initial
  sig.set(2)
  inspect(ops.dep_changed_since(Revision::initial()), content="Some(true)")
}

///|
test "cell_ops: memo dep_changed_since returns None" {
  let rt = Runtime::new()
  let sig = Signal::new(rt, 1)
  let m = Memo::new(rt, () => sig.get())
  let _ = m.get()
  let ops = rt.core.cell_ops[m.id().id]
  // Memo-like cells return None (requires deep verification)
  inspect(ops.dep_changed_since(Revision::initial()), content="None")
}

///|
test "cell_ops: memo level defaults to 0" {
  let rt = Runtime::new()
  let m = Memo::new(rt, () => 0)
  let ops = rt.core.cell_ops[m.id().id]
  inspect(ops.level(), content="0")
}

///|
test "cell_ops: push reactive level returns stored level" {
  let rt = Runtime::new()
  let sig = Signal::new(rt, 1)
  let r = Reactive::new(rt, () => sig.get())
  let ops = rt.core.cell_ops[r.id().id]
  // Push reactive level = max(source levels) + 1 = 0 + 1 = 1
  inspect(ops.level(), content="1")
}

///|
test "cell_ops: push reactive dep_changed_since returns Some" {
  let rt = Runtime::new()
  let sig = Signal::new(rt, 1)
  let r = Reactive::new(rt, () => sig.get())
  let ops = rt.core.cell_ops[r.id().id]
  // Push reactive uses the default (leaf-cell) dep_changed_since
  inspect(ops.dep_changed_since(Revision::initial()), content="Some(false)")
}

///|
test "cell_ops: hybrid memo dep_changed_since returns None" {
  let rt = Runtime::new()
  let sig = Signal::new(rt, 1)
  let hm = HybridMemo::new(rt, () => sig.get())
  let _ = hm.get()
  let ops = rt.core.cell_ops[hm.id().id]
  // Hybrid memo-like cells return None (requires deep verification)
  inspect(ops.dep_changed_since(Revision::initial()), content="None")
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
