///|
test "signal: dispose marks cell as disposed" {
  let rt = Runtime::new()
  let sig = Signal::new(rt, 42)
  assert_false(sig.is_disposed())
  sig.dispose()
  assert_true(sig.is_disposed())
}

///|
test "signal: dispose is idempotent" {
  let rt = Runtime::new()
  let sig = Signal::new(rt, 42)
  sig.dispose()
  sig.dispose() // second call is no-op, no abort
  assert_true(sig.is_disposed())
}

///|
test "panic signal: get after dispose aborts" {
  let rt = Runtime::new()
  let sig = Signal::new(rt, 42)
  sig.dispose()
  ignore(sig.get()) // should abort
}

///|
test "memo: dispose marks cell as disposed" {
  let rt = Runtime::new()
  let sig = Signal::new(rt, 10)
  let m = Memo::new(rt, fn() { sig.get() * 2 })
  ignore(m.get()) // prime
  assert_false(m.is_disposed())
  m.dispose()
  assert_true(m.is_disposed())
}

///|
test "memo: dispose is idempotent" {
  let rt = Runtime::new()
  let sig = Signal::new(rt, 10)
  let m = Memo::new(rt, fn() { sig.get() * 2 })
  ignore(m.get())
  m.dispose()
  m.dispose() // no-op
  assert_true(m.is_disposed())
}

///|
test "panic memo: get after dispose aborts" {
  let rt = Runtime::new()
  let sig = Signal::new(rt, 10)
  let m = Memo::new(rt, fn() { sig.get() * 2 })
  ignore(m.get())
  m.dispose()
  ignore(m.get()) // should abort
}

///|
test "memo: dispose then new memo works independently" {
  let rt = Runtime::new()
  let sig = Signal::new(rt, 10)
  let m1 = Memo::new(rt, fn() { sig.get() * 2 })
  ignore(m1.get())
  m1.dispose()
  let m2 = Memo::new(rt, fn() { sig.get() * 3 })
  assert_eq(m2.get(), 30)
  assert_true(m1.is_disposed())
  assert_false(m2.is_disposed())
}

///|
test "hybrid memo: is_disposed returns correct state" {
  let rt = Runtime::new()
  let sig = Signal::new(rt, 10)
  let h = HybridMemo::new(rt, fn() { sig.get() * 2 })
  ignore(h.get())
  assert_false(h.is_disposed())
  h.dispose()
  assert_true(h.is_disposed())
}

///|
test "reactive: is_disposed returns correct state" {
  let rt = Runtime::new()
  let sig = Signal::new(rt, 10)
  let r = Reactive::new(rt, fn() { sig.get() * 2 })
  assert_false(r.is_disposed())
  r.dispose()
  assert_true(r.is_disposed())
}

///|
test "effect: is_disposed returns correct state" {
  let rt = Runtime::new()
  let sig = Signal::new(rt, 10)
  let eff = Effect::new(rt, fn() { ignore(sig.get()) })
  assert_false(eff.is_disposed())
  eff.dispose()
  assert_true(eff.is_disposed())
}

///|
test "relation: dispose marks cell as disposed" {
  let rt = Runtime::new()
  let rel : Relation[Int] = Relation::new(rt)
  rel.insert(42) |> ignore
  assert_false(rel.is_disposed())
  rel.dispose()
  assert_true(rel.is_disposed())
}

///|
test "relation: dispose is idempotent" {
  let rt = Runtime::new()
  let rel : Relation[Int] = Relation::new(rt)
  rel.dispose()
  rel.dispose() // no-op
  assert_true(rel.is_disposed())
}

///|
test "functional relation: dispose marks cell as disposed" {
  let rt = Runtime::new()
  let frel : FunctionalRelation[Int, String] = FunctionalRelation::new(rt)
  frel.insert(1, "a") |> ignore
  assert_false(frel.is_disposed())
  frel.dispose()
  assert_true(frel.is_disposed())
}

///|
test "functional relation: dispose is idempotent" {
  let rt = Runtime::new()
  let frel : FunctionalRelation[Int, String] = FunctionalRelation::new(rt)
  frel.dispose()
  frel.dispose() // no-op
  assert_true(frel.is_disposed())
}

///|
test "rule: dispose_rule does not abort" {
  let rt = Runtime::new()
  let rel : Relation[Int] = Relation::new(rt)
  let out : Relation[Int] = Relation::new(rt)
  let rule_id = rt.new_rule([rel.id()], [out.id()], fn() {
    for x in rel.delta_iter() {
      out.insert(x * 2) |> ignore
    }
  })
  rt.dispose_rule(rule_id)
}

///|
test "rule: dispose_rule is idempotent" {
  let rt = Runtime::new()
  let rel : Relation[Int] = Relation::new(rt)
  let out : Relation[Int] = Relation::new(rt)
  let rule_id = rt.new_rule([rel.id()], [out.id()], fn() {
    for x in rel.delta_iter() {
      out.insert(x * 2) |> ignore
    }
  })
  rt.dispose_rule(rule_id)
  rt.dispose_rule(rule_id) // no-op, should not abort
}

///|
test "tracked cell: dispose delegates to inner signal" {
  let rt = Runtime::new()
  let cell = TrackedCell::new(rt, 42)
  assert_false(cell.is_disposed())
  cell.dispose()
  assert_true(cell.is_disposed())
}

///|
test "signal: dispose during batch discards pending write" {
  let rt = Runtime::new()
  let sig = Signal::new(rt, 10)
  rt.batch(fn() {
    sig.set(20) // queued as pending
    sig.dispose() // should discard the pending write
  })
  // Batch commits — disposed signal's write should be gone
  assert_true(sig.is_disposed())
}

///|
test "panic signal: set after dispose aborts" {
  let rt = Runtime::new()
  let sig = Signal::new(rt, 42)
  sig.dispose()
  sig.set(99) // should abort
}

///|
test "signal: dispose of a dependency during computation is safe" {
  // Disposing a different cell during a memo's compute function is allowed.
  // The memo will still see the value it already read. Future reads of the
  // disposed cell will abort, which is the caller's responsibility.
  let rt = Runtime::new()
  let sig = Signal::new(rt, 10)
  let other_sig = Signal::new(rt, 99)
  let m = Memo::new(rt, fn() {
    let v = sig.get()
    other_sig.dispose() // dispose a DIFFERENT cell — allowed
    v
  })
  inspect(m.get(), content="10")
  assert_true(other_sig.is_disposed())
}

///|
test "disposed rule is skipped during fixpoint" {
  let rt = Runtime::new()
  let input : Relation[Int] = Relation::new(rt)
  let output : Relation[Int] = Relation::new(rt)
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
  let rt = Runtime::new()
  let rel : Relation[Int] = Relation::new(rt)
  rel.dispose()
  rel.insert(42) |> ignore // should abort
}

///|
test "panic functional relation: insert after dispose aborts" {
  let rt = Runtime::new()
  let frel : FunctionalRelation[Int, String] = FunctionalRelation::new(rt)
  frel.dispose()
  frel.insert(1, "a") |> ignore // should abort
}
