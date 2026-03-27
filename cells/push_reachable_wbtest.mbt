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

///|
test "push_reachable_count: source change on reactive recompute" {
  let rt = Runtime::new()
  let s1 = Signal::new(rt, 0)
  let s2 = Signal::new(rt, 0)
  // reactive starts reading s1
  let flag : Ref[Bool] = Ref::new(true)
  let r = Reactive::new(rt, () => if flag.val { s1.get() } else { s2.get() })
  inspect(get_count(rt, s1.id()), content="1")
  inspect(get_count(rt, s2.id()), content="0")
  // switch reactive to read s2 by changing flag and triggering recompute
  flag.val = false
  s1.set(1) // triggers push propagation -> r recomputes -> now reads s2
  inspect(get_count(rt, s1.id()), content="0")
  inspect(get_count(rt, s2.id()), content="1")
}

///|
test "push_reachable_count: memo dep change updates upstream signal counts" {
  let rt = Runtime::new()
  let s1 = Signal::new(rt, 0)
  let s2 = Signal::new(rt, 0)
  let flag : Ref[Bool] = Ref::new(true)
  // memoA conditionally reads s1 or s2
  let mA = Memo::new(rt, () => if flag.val { s1.get() } else { s2.get() })
  // reactive reads memoA (forces memoA to compute -> deps=[s1])
  let _r = Reactive::new(rt, () => mA.get())
  inspect(get_count(rt, s1.id()), content="1")
  inspect(get_count(rt, s2.id()), content="0")
  // switch memoA to read s2: change flag, trigger recompute via signal change
  flag.val = false
  s1.set(1) // reactive recomputes -> pull_verify memoA -> memo recomputes -> s2 added
  inspect(get_count(rt, s1.id()), content="0")
  inspect(get_count(rt, s2.id()), content="1")
}

///|
test "push_reachable_count: hybrid memo dispose decrements upstream" {
  let rt = Runtime::new()
  let s = Signal::new(rt, 0)
  let h = HybridMemo::new(rt, () => s.get())
  let _r = Reactive::new(rt, () => h.get())
  inspect(get_count(rt, s.id()), content="1")
  inspect(get_count(rt, h.id()), content="1")
  h.dispose()
  // After h is disposed, s should have count 0
  inspect(get_count(rt, s.id()), content="0")
}

///|
test "push_reachable_count: no push cells = zero everywhere" {
  let rt = Runtime::new()
  let s = Signal::new(rt, 0)
  let _m = Memo::new(rt, () => s.get())
  inspect(get_count(rt, s.id()), content="0")
}

///|
test "gate: signal with count 0 does not trigger reactive on separate signal" {
  let rt = Runtime::new()
  let s1 = Signal::new(rt, 0)
  let s2 = Signal::new(rt, 0)
  let mut recomputes = 0
  let _r = Reactive::new(rt, () => {
    recomputes = recomputes + 1
    s2.get()
  })
  let initial = recomputes
  // s1 has no downstream push cells (r reads s2, not s1)
  inspect(get_count(rt, s1.id()), content="0")
  // Changing s1 should NOT trigger r to recompute
  s1.set(1)
  inspect(recomputes, content=initial.to_string())
}
