///|
test "functional_relation: insert and get after fixpoint" {
  let rt = Runtime::new()
  let fr : FunctionalRelation[String, Int] = FunctionalRelation::new(rt)
  let inserted = fr.insert("x", 42)
  inspect(inserted, content="true")
  // Not visible via get before fixpoint (still in delta)
  inspect(fr.get("x"), content="None")
  rt.fixpoint()
  // Visible after fixpoint drains delta into current
  inspect(fr.get("x"), content="Some(42)")
}

///|
test "functional_relation: insert same key with different value replaces" {
  let rt = Runtime::new()
  let fr : FunctionalRelation[String, Int] = FunctionalRelation::new(rt)
  let first = fr.insert("x", 1)
  inspect(first, content="true")
  let second = fr.insert("x", 2)
  inspect(second, content="true")
  rt.fixpoint()
  inspect(fr.get("x"), content="Some(2)")
}

///|
test "functional_relation: insert same key with same value is no-op" {
  let rt = Runtime::new()
  let fr : FunctionalRelation[String, Int] = FunctionalRelation::new(rt)
  let first = fr.insert("x", 1)
  inspect(first, content="true")
  let dup = fr.insert("x", 1)
  inspect(dup, content="false")
}

///|
test "functional_relation: effective value checked across layers" {
  let rt = Runtime::new()
  let fr : FunctionalRelation[String, Int] = FunctionalRelation::new(rt)
  // Insert x=1 into delta
  let ins1 = fr.insert("x", 1)
  inspect(ins1, content="true")
  // Insert x=1 again — effective value in delta is already 1, no-op
  let ins2 = fr.insert("x", 1)
  inspect(ins2, content="false")
  // Insert x=2 — effective value in delta is 1, so this is a change
  let ins3 = fr.insert("x", 2)
  inspect(ins3, content="true")
  // Insert x=2 again — effective value in delta is now 2, no-op
  let ins4 = fr.insert("x", 2)
  inspect(ins4, content="false")
}

///|
test "functional_relation: merge function resolves conflicts" {
  let rt = Runtime::new()
  let fr : FunctionalRelation[String, Int] = FunctionalRelation::new(rt, merge=fn(
    a,
    b,
  ) {
    if a > b {
      a
    } else {
      b
    }
  })
  // Insert x=10
  let ins1 = fr.insert("x", 10)
  inspect(ins1, content="true")
  rt.fixpoint()
  inspect(fr.get("x"), content="Some(10)")
  // Insert x=20 — merge(10, 20) = 20, changed
  let ins2 = fr.insert("x", 20)
  inspect(ins2, content="true")
  rt.fixpoint()
  inspect(fr.get("x"), content="Some(20)")
  // Insert x=5 — merge(20, 5) = 20, same as current, no-op
  let ins3 = fr.insert("x", 5)
  inspect(ins3, content="false")
}

///|
test "functional_relation: delta_iter shows new and updated entries" {
  let rt = Runtime::new()
  let fr : FunctionalRelation[String, Int] = FunctionalRelation::new(rt)
  fr.insert("a", 1) |> ignore
  fr.insert("b", 2) |> ignore
  let count = fr.delta_iter().fold(init=0, fn(acc, _kv) { acc + 1 })
  inspect(count, content="2")
}

///|
test "functional_relation: iter reads current after fixpoint" {
  let rt = Runtime::new()
  let fr : FunctionalRelation[String, Int] = FunctionalRelation::new(rt)
  fr.insert("a", 1) |> ignore
  fr.insert("b", 2) |> ignore
  // Before fixpoint, iter reads current which is empty
  let before = fr.iter().fold(init=0, fn(acc, _kv) { acc + 1 })
  inspect(before, content="0")
  rt.fixpoint()
  // After fixpoint, iter reads current which has entries
  let after = fr.iter().fold(init=0, fn(acc, _kv) { acc + 1 })
  inspect(after, content="2")
}

///|
test "functional_relation: value update produces delta in next fixpoint" {
  let rt = Runtime::new()
  let fr : FunctionalRelation[String, Int] = FunctionalRelation::new(rt)
  fr.insert("x", 1) |> ignore
  rt.fixpoint()
  inspect(fr.get("x"), content="Some(1)")
  // Insert x=2 — replaces value
  let changed = fr.insert("x", 2)
  inspect(changed, content="true")
  // delta should have 1 entry
  let delta_count = fr.delta_iter().fold(init=0, fn(acc, _kv) { acc + 1 })
  inspect(delta_count, content="1")
  rt.fixpoint()
  inspect(fr.get("x"), content="Some(2)")
}

///|
test "functional_relation: no-op convergence terminates" {
  let rt = Runtime::new()
  let fr : FunctionalRelation[String, Int] = FunctionalRelation::new(rt)
  // Rule that always re-inserts the same value — must not loop forever
  let _ = rt.new_rule([fr.id()], [fr.id()], fn() {
    for kv in fr.delta_iter() {
      fr.insert(kv.0, kv.1) |> ignore
    }
  })
  fr.insert("x", 1) |> ignore
  rt.fixpoint() // must terminate
  inspect(fr.get("x"), content="Some(1)")
}

///|
test "functional_relation: memo recomputes after fixpoint changes value" {
  let rt = Runtime::new()
  let fr : FunctionalRelation[String, Int] = FunctionalRelation::new(rt)
  let _ = fr.insert("x", 1)
  rt.fixpoint()
  let m = Memo::new(rt, fn() { fr.get("x").unwrap_or(0) })
  inspect(m.get(), content="1")
  let _ = fr.insert("x", 2)
  rt.fixpoint()
  inspect(m.get(), content="2")
}

///|
test "panic functional_relation: cross-runtime read aborts" {
  let rt1 = Runtime::new()
  let rt2 = Runtime::new()
  let fr : FunctionalRelation[String, Int] = FunctionalRelation::new(rt1)
  let _ = fr.insert("x", 1)
  rt1.fixpoint()
  let memo = Memo::new(rt2, fn() { fr.get("x").unwrap_or(0) })
  let _ = memo.get()
}

///|
test "functional_relation: mixed Relation and FunctionalRelation rule" {
  let rt = Runtime::new()
  let edges : Relation[(Int, Int)] = Relation::new(rt)
  let weights : FunctionalRelation[(Int, Int), Int] = FunctionalRelation::new(
    rt,
  )
  let _ = edges.insert((1, 2))
  let _ = rt.new_rule([edges.id()], [weights.id()], fn() {
    for e in edges.delta_iter() {
      let _ = weights.insert(e, 1)
    }
  })
  rt.fixpoint()
  inspect(weights.get((1, 2)), content="Some(1)")
}

///|
test "functional_relation: multiple writes to same key converges" {
  let rt = Runtime::new()
  let fr : FunctionalRelation[String, Int] = FunctionalRelation::new(rt)
  let _ = fr.insert("x", 1)
  let _ = rt.new_rule([fr.id()], [fr.id()], fn() {
    for entry in fr.delta_iter() {
      let (k, v) = entry
      if v < 10 {
        let _ = fr.insert(k, v + 1)
      }
    }
  })
  rt.fixpoint()
  inspect(fr.get("x"), content="Some(10)")
}

///|
test "functional_relation: created during rule execution converges" {
  let rt = Runtime::new()
  let trigger : Relation[Int] = Relation::new(rt)
  let _ = trigger.insert(1)
  let dynamic_fr_ref : Ref[FunctionalRelation[Int, Int]?] = { val: None }
  let _ = rt.new_rule([trigger.id()], [], fn() {
    for _ in trigger.delta_iter() {
      let fr : FunctionalRelation[Int, Int] = FunctionalRelation::new(rt)
      let _ = fr.insert(1, 42)
      dynamic_fr_ref.val = Some(fr)
    }
  })
  rt.fixpoint()
  match dynamic_fr_ref.val {
    Some(fr) => inspect(fr.get(1), content="Some(42)")
    None => abort("dynamic fr not created")
  }
}
