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
  let _ = rt.read(m)
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
  let _ = rt.read_hybrid(hm)
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

///|
test "gc_role: signal is Source" {
  let rt = Runtime::new()
  let sig = Signal::new(rt, 42)
  let ops = rt.core.cell_ops[sig.id().id]
  inspect(ops.gc_role(), content="Source")
  sig.dispose()
}

///|
test "gc_role: memo is Interior" {
  let rt = Runtime::new()
  let sig = Signal::new(rt, 10)
  let m = Memo::new(rt, fn() { sig.get() })
  let ops = rt.core.cell_ops[m.id().id]
  inspect(ops.gc_role(), content="Interior")
  m.dispose()
  sig.dispose()
}

///|
test "gc_role: reactive is Interior" {
  let rt = Runtime::new()
  let sig = Signal::new(rt, 1)
  let r = Reactive::new(rt, fn() { sig.get() })
  let ops = rt.core.cell_ops[r.id().id]
  inspect(ops.gc_role(), content="Interior")
  r.dispose()
  sig.dispose()
}

///|
test "gc_role: effect is Root" {
  let rt = Runtime::new()
  let sig = Signal::new(rt, 1)
  let eff = Effect::new(rt, fn() { ignore(sig.get()) })
  let ops = rt.core.cell_ops[eff.id().id]
  inspect(ops.gc_role(), content="Root")
  eff.dispose()
  sig.dispose()
}

///|
test "gc_dependencies: signal has empty deps" {
  let rt = Runtime::new()
  let sig = Signal::new(rt, 42)
  let ops = rt.core.cell_ops[sig.id().id]
  inspect(ops.gc_dependencies().length(), content="0")
  sig.dispose()
}

///|
test "gc_dependencies: memo returns its dependencies" {
  let rt = Runtime::new()
  let sig = Signal::new(rt, 10)
  let m = Memo::new(rt, fn() { sig.get() })
  let _ = rt.read(m)
  let ops = rt.core.cell_ops[m.id().id]
  let deps = ops.gc_dependencies()
  inspect(deps.length(), content="1")
  inspect(deps[0] == sig.id(), content="true")
  m.dispose()
  sig.dispose()
}

///|
test "gc_dependencies: effect returns its sources" {
  let rt = Runtime::new()
  let sig = Signal::new(rt, 1)
  let eff = Effect::new(rt, fn() { ignore(sig.get()) })
  let ops = rt.core.cell_ops[eff.id().id]
  let deps = ops.gc_dependencies()
  inspect(deps.length(), content="1")
  inspect(deps[0] == sig.id(), content="true")
  eff.dispose()
  sig.dispose()
}

///|
test "cell_lifecycle: dispose_cell dispatches via lifecycle array for memo" {
  let rt = Runtime::new()
  let sig = Signal::new(rt, 10)
  let m = Memo::new(rt, fn() { sig.get() })
  let _ = rt.read(m)
  // Verify lifecycle array is populated
  inspect(rt.core.cell_lifecycle.length(), content="2")
  // Dispose via dispose_cell (uses cell_lifecycle dispatch)
  rt.dispose_cell(m.id())
  inspect(m.is_disposed(), content="true")
  // Signal still alive
  inspect(sig.is_disposed(), content="false")
  sig.dispose()
}

///|
test "cell_lifecycle: dispose_cell dispatches via lifecycle array for relation" {
  let rt = Runtime::new()
  let rel : Relation[Int] = Relation::new(rt)
  rel.insert(42) |> ignore
  // Verify lifecycle array is populated
  inspect(rt.core.cell_lifecycle.length(), content="1")
  rt.dispose_cell(rel.id())
  inspect(rel.is_disposed(), content="true")
}

///|
test "is_hybrid: memo has is_hybrid false" {
  let rt = Runtime::new()
  let sig = Signal::new(rt, 10)
  let m = Memo::new(rt, fn() { sig.get() })
  inspect(rt.pull.memos[0].is_hybrid, content="false")
  m.dispose()
  sig.dispose()
}

///|
test "is_hybrid: hybrid memo has is_hybrid true" {
  let rt = Runtime::new()
  let sig = Signal::new(rt, 10)
  let hm = HybridMemo::new(rt, fn() { sig.get() })
  inspect(rt.pull.memos[0].is_hybrid, content="true")
  hm.dispose()
  sig.dispose()
}
