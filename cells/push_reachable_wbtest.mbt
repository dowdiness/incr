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

///|
test "collect_reachable_cells: signal returns {signal}" {
  let rt = Runtime::new()
  let s = Signal::new(rt, 0)
  let cells = rt.collect_reachable_cells([s.id()])
  inspect(cells.contains(s.id()), content="true")
  inspect(cells.length(), content="1")
}

///|
test "collect_reachable_cells: memo returns memo + upstream signal" {
  let rt = Runtime::new()
  let s = Signal::new(rt, 0)
  let m = Memo::new(rt, () => s.get())
  ignore(m.get()) // force compute so dependencies are recorded
  let cells = rt.collect_reachable_cells([m.id()])
  inspect(cells.contains(m.id()), content="true")
  inspect(cells.contains(s.id()), content="true")
  inspect(cells.length(), content="2")
}

///|
test "collect_reachable_cells: uncomputed memo returns only memo" {
  let rt = Runtime::new()
  let s = Signal::new(rt, 0)
  let m = Memo::new(rt, () => s.get())
  // m.get() NOT called — dependencies array is empty
  let cells = rt.collect_reachable_cells([m.id()])
  inspect(cells.contains(m.id()), content="true")
  inspect(cells.length(), content="1")
}

///|
test "push_contribution: reactive returns 1" {
  let rt = Runtime::new()
  let s = Signal::new(rt, 0)
  let r = Reactive::new(rt, () => s.get())
  inspect(rt.push_contribution(r.id()), content="1")
}

///|
test "push_contribution: signal returns 0" {
  let rt = Runtime::new()
  let s = Signal::new(rt, 0)
  inspect(rt.push_contribution(s.id()), content="0")
}

///|
/// Helper: read push_reachable_count from any cell via cell_index.
fn get_count(rt : Runtime, id : CellId) -> Int {
  match rt.core.cell_index[id.id] {
    PullSignal(i) => rt.pull.signals[i].meta.push_reachable_count
    PullMemo(i) | HybridMemo(i) => rt.pull.memos[i].meta.push_reachable_count
    PushReactive(i) => rt.push.reactives[i].meta.push_reachable_count
    PushEffect(i) => rt.push.effects[i].meta.push_reachable_count
    Relation(i) => rt.datalog.relations[i].meta.push_reachable_count
    FunctionalRelation(i) =>
      rt.datalog.functional_relations[i].meta.push_reachable_count
    Rule(i) => rt.datalog.rules[i].meta.push_reachable_count
    Disposed => 0
  }
}

///|
test "push_reachable_count: signal with direct reactive counts 1" {
  let rt = Runtime::new()
  let s = Signal::new(rt, 0)
  let _r = Reactive::new(rt, () => s.get())
  inspect(get_count(rt, s.id()), content="1")
}

///|
test "push_reachable_count: signal with reactive through hybrid memo" {
  let rt = Runtime::new()
  let s = Signal::new(rt, 0)
  let h = HybridMemo::new(rt, () => s.get())
  let _r = Reactive::new(rt, () => h.get())
  inspect(get_count(rt, s.id()), content="1")
  inspect(get_count(rt, h.id()), content="1")
}

///|
test "push_reachable_count: two-deep memo chain" {
  let rt = Runtime::new()
  let s = Signal::new(rt, 0)
  let mA = Memo::new(rt, () => s.get())
  let mB = Memo::new(rt, () => mA.get())
  let _r = Reactive::new(rt, () => mB.get())
  inspect(get_count(rt, s.id()), content="1")
  inspect(get_count(rt, mA.id()), content="1")
  inspect(get_count(rt, mB.id()), content="1")
}

///|
test "push_reachable_count: diamond topology" {
  let rt = Runtime::new()
  let s = Signal::new(rt, 0)
  let mA = Memo::new(rt, () => s.get() + 1)
  let mB = Memo::new(rt, () => s.get() + 2)
  let _r = Reactive::new(rt, () => mA.get() + mB.get())
  // Two paths: s->mA->r and s->mB->r
  inspect(get_count(rt, s.id()), content="2")
  inspect(get_count(rt, mA.id()), content="1")
  inspect(get_count(rt, mB.id()), content="1")
}

///|
test "push_reachable_count: reactive dispose returns counts to 0" {
  let rt = Runtime::new()
  let s = Signal::new(rt, 0)
  let r = Reactive::new(rt, () => s.get())
  inspect(get_count(rt, s.id()), content="1")
  r.dispose()
  inspect(get_count(rt, s.id()), content="0")
}

///|
test "push_reachable_count: diamond dispose returns to 0" {
  let rt = Runtime::new()
  let s = Signal::new(rt, 0)
  let mA = Memo::new(rt, () => s.get() + 1)
  let mB = Memo::new(rt, () => s.get() + 2)
  let r = Reactive::new(rt, () => mA.get() + mB.get())
  inspect(get_count(rt, s.id()), content="2")
  r.dispose()
  inspect(get_count(rt, s.id()), content="0")
  inspect(get_count(rt, mA.id()), content="0")
  inspect(get_count(rt, mB.id()), content="0")
}

///|
test "push_reachable_count: relation-to-reactive" {
  let rt = Runtime::new()
  let rel : Relation[Int] = Relation::new(rt)
  let mut count = 0
  let r = Reactive::new(rt, () => {
    count = count + 1
    rel.iter().fold(init=0, fn(acc, x) { acc + x })
  })
  ignore(r) // r is alive
  inspect(get_count(rt, rel.id()), content="1")
  r.dispose()
  inspect(get_count(rt, rel.id()), content="0")
}

///|
test "push_reachable_count: reactive-to-reactive chain" {
  let rt = Runtime::new()
  let s = Signal::new(rt, 0)
  let r1 = Reactive::new(rt, () => s.get() + 1)
  let _r2 = Reactive::new(rt, () => r1.get() + 1)
  inspect(get_count(rt, s.id()), content="1")
  inspect(get_count(rt, r1.id()), content="1")
}
