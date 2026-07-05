///|
test "input: dispose marks cell as disposed" {
  let rt = Runtime::Runtime()
  let sig = Input::Input(rt, 42)
  assert_false(sig.is_disposed())
  sig.dispose()
  assert_true(sig.is_disposed())
}

///|
test "input: dispose is idempotent" {
  let rt = Runtime::Runtime()
  let sig = Input::Input(rt, 42)
  sig.dispose()
  sig.dispose() // second call is no-op, no abort
  assert_true(sig.is_disposed())
}

///|
test "panic input: get after dispose aborts" {
  let rt = Runtime::Runtime()
  let sig = Input::Input(rt, 42)
  sig.dispose()
  ignore(sig.get()) // should abort
}

///|
test "derived: dispose marks cell as disposed" {
  let rt = Runtime::Runtime()
  let sig = Input::Input(rt, 10)
  let d = Derived::Derived(rt, fn() { sig.get() * 2 })
  ignore(d.read_or_abort()) // prime
  assert_false(d.is_disposed())
  d.dispose()
  assert_true(d.is_disposed())
}

///|
test "derived: dispose is idempotent" {
  let rt = Runtime::Runtime()
  let sig = Input::Input(rt, 10)
  let d = Derived::Derived(rt, fn() { sig.get() * 2 })
  ignore(d.read_or_abort())
  d.dispose()
  d.dispose() // no-op
  assert_true(d.is_disposed())
}

///|
test "panic derived: read_or_abort after dispose aborts" {
  let rt = Runtime::Runtime()
  let sig = Input::Input(rt, 10)
  let d = Derived::Derived(rt, fn() { sig.get() * 2 })
  ignore(d.read_or_abort())
  d.dispose()
  ignore(d.read_or_abort()) // should abort
}

///|
test "derived: dispose then new derived works independently" {
  let rt = Runtime::Runtime()
  let sig = Input::Input(rt, 10)
  let d1 = Derived::Derived(rt, fn() { sig.get() * 2 })
  ignore(d1.read_or_abort())
  d1.dispose()
  let d2 = Derived::Derived(rt, fn() { sig.get() * 3 })
  assert_eq(d2.read_or_abort(), 30)
  assert_true(d1.is_disposed())
  assert_false(d2.is_disposed())
}

///|
test "reachable derived: is_disposed returns correct state" {
  let rt = Runtime::Runtime()
  let sig = Input::Input(rt, 10)
  let rd = ReachableDerived::ReachableDerived(rt, fn() { sig.get() * 2 })
  ignore(rd.read_or_abort())
  assert_false(rd.is_disposed())
  rd.dispose()
  assert_true(rd.is_disposed())
}

///|
test "reactive: is_disposed returns correct state" {
  let rt = Runtime::Runtime()
  let sig = Input::Input(rt, 10)
  let r = EagerDerived::EagerDerived(rt, fn() { sig.get() * 2 })
  assert_false(r.is_disposed())
  r.dispose()
  assert_true(r.is_disposed())
}

///|
test "effect: is_disposed returns correct state" {
  let rt = Runtime::Runtime()
  let sig = Input::Input(rt, 10)
  let eff = Effect::Effect(rt, fn() { ignore(sig.get()) })
  assert_false(eff.is_disposed())
  eff.dispose()
  assert_true(eff.is_disposed())
}

///|
test "relation: dispose marks cell as disposed" {
  let rt = Runtime::Runtime()
  let rel : Relation[Int] = Relation::Relation(rt)
  rel.insert(42) |> ignore
  assert_false(rel.is_disposed())
  rel.dispose()
  assert_true(rel.is_disposed())
}

///|
test "relation: dispose is idempotent" {
  let rt = Runtime::Runtime()
  let rel : Relation[Int] = Relation::Relation(rt)
  rel.dispose()
  rel.dispose() // no-op
  assert_true(rel.is_disposed())
}

///|
test "map relation: dispose marks cell as disposed" {
  let rt = Runtime::Runtime()
  let frel : MapRelation[Int, String] = MapRelation::MapRelation(rt)
  frel.insert(1, "a") |> ignore
  assert_false(frel.is_disposed())
  frel.dispose()
  assert_true(frel.is_disposed())
}

///|
test "map relation: dispose is idempotent" {
  let rt = Runtime::Runtime()
  let frel : MapRelation[Int, String] = MapRelation::MapRelation(rt)
  frel.dispose()
  frel.dispose() // no-op
  assert_true(frel.is_disposed())
}

///|
test "rule: dispose_rule does not abort" {
  let rt = Runtime::Runtime()
  let rel : Relation[Int] = Relation::Relation(rt)
  let out : Relation[Int] = Relation::Relation(rt)
  let rule_id = rt.new_rule([rel.id()], [out.id()], fn() {
    for x in rel.delta_iter() {
      out.insert(x * 2) |> ignore
    }
  })
  rt.dispose_rule(rule_id)
}

///|
test "rule: dispose_rule is idempotent" {
  let rt = Runtime::Runtime()
  let rel : Relation[Int] = Relation::Relation(rt)
  let out : Relation[Int] = Relation::Relation(rt)
  let rule_id = rt.new_rule([rel.id()], [out.id()], fn() {
    for x in rel.delta_iter() {
      out.insert(x * 2) |> ignore
    }
  })
  rt.dispose_rule(rule_id)
  rt.dispose_rule(rule_id) // no-op, should not abort
}

///|
test "input field: dispose delegates to inner input" {
  let rt = Runtime::Runtime()
  let cell = InputField::InputField(rt, 42)
  assert_false(cell.is_disposed())
  cell.dispose()
  assert_true(cell.is_disposed())
}

///|
test "input: dispose during batch discards pending write" {
  let rt = Runtime::Runtime()
  let sig = Input::Input(rt, 10)
  rt.batch(fn() {
    sig.set(20) // queued as pending
    sig.dispose() // should discard the pending write
  })
  // Batch commits — disposed input's write should be gone
  assert_true(sig.is_disposed())
}

///|
test "panic input: set after dispose aborts" {
  let rt = Runtime::Runtime()
  let sig = Input::Input(rt, 42)
  sig.dispose()
  sig.set(99) // should abort
}

///|
test "input: dispose of a dependency during computation is safe" {
  // Disposing a different cell during a memo's compute function is allowed.
  // The memo will still see the value it already read. Future reads of the
  // disposed cell will abort, which is the caller's responsibility.
  let rt = Runtime::Runtime()
  let sig = Input::Input(rt, 10)
  let other_sig = Input::Input(rt, 99)
  let d = Derived::Derived(rt, fn() {
    let v = sig.get()
    other_sig.dispose() // dispose a DIFFERENT cell — allowed
    v
  })
  inspect(d.read_or_abort(), content="10")
  assert_true(other_sig.is_disposed())
}

///|
test "disposed rule is skipped during fixpoint" {
  let rt = Runtime::Runtime()
  let input : Relation[Int] = Relation::Relation(rt)
  let output : Relation[Int] = Relation::Relation(rt)
  let rule_id = rt.new_rule([input.id()], [output.id()], fn() {
    for x in input.delta_iter() {
      output.insert(x * 10) |> ignore
    }
  })
  input.insert(1) |> ignore
  rt.fixpoint()
  assert_true(output.contains(10))
  // Dispose rule, add more input, run fixpoint again
  rt.dispose_rule(rule_id)
  input.insert(2) |> ignore
  rt.fixpoint()
  // Rule was disposed — 2*10=20 should NOT appear in output
  assert_false(output.contains(20))
}

///|
test "panic relation: insert after dispose aborts" {
  let rt = Runtime::Runtime()
  let rel : Relation[Int] = Relation::Relation(rt)
  rel.dispose()
  rel.insert(42) |> ignore // should abort
}

///|
test "panic functional relation: insert after dispose aborts" {
  let rt = Runtime::Runtime()
  let frel : MapRelation[Int, String] = MapRelation::MapRelation(rt)
  frel.dispose()
  frel.insert(1, "a") |> ignore // should abort
}

///|
test "dispose_cell: dispatches to correct dispose method for each cell type" {
  let rt = Runtime::Runtime()
  let sig = Input::Input(rt, 10)
  let d = Derived::Derived(rt, fn() { sig.get() * 2 })
  let rd = ReachableDerived::ReachableDerived(rt, fn() { sig.get() + 1 })
  // Force memos to compute so they have dependencies
  let _ = d.read_or_abort()
  let _ = rd.read_or_abort()
  // Dispose via generic dispatcher
  rt.dispose_cell(sig.id())
  rt.dispose_cell(d.id())
  rt.dispose_cell(rd.id())
  inspect(sig.is_disposed(), content="true")
  inspect(d.is_disposed(), content="true")
  inspect(rd.is_disposed(), content="true")
}

///|
test "dispose_cell: idempotent — disposing already-disposed cell is no-op" {
  let rt = Runtime::Runtime()
  let sig = Input::Input(rt, 42)
  rt.dispose_cell(sig.id())
  // Second dispose should not abort
  rt.dispose_cell(sig.id())
  inspect(sig.is_disposed(), content="true")
}

///|
test "dispose_cell: push reactive and effect" {
  let rt = Runtime::Runtime()
  let sig = Input::Input(rt, 1)
  let reactive : EagerDerived[Int] = EagerDerived::EagerDerived(rt, fn() {
    sig.get()
  })
  let effect_ran : Ref[Int] = { val: 0 }
  let eff = Effect::Effect(rt, fn() {
    effect_ran.val = effect_ran.val + sig.get()
  })
  rt.dispose_cell(reactive.id())
  rt.dispose_cell(eff.id())
  inspect(reactive.is_disposed(), content="true")
  inspect(eff.is_disposed(), content="true")
}

///|
test "panic dispose_cell: rejects foreign runtime CellId" {
  let rt1 = Runtime::Runtime()
  let rt2 = Runtime::Runtime()
  let sig = Input::Input(rt1, 42)
  // Attempting to dispose rt1's cell via rt2 should abort
  rt2.dispose_cell(sig.id())
}
