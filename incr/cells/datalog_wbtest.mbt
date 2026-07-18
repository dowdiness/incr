///|
test "cell_ref: Relation and Rule variants exist" {
  let a : CellRef = CellRef::Relation(0)
  let b : CellRef = CellRef::Rule(1)
  let ia = match a {
    Relation(i) => i
    _ => -1
  }
  let ib = match b {
    Rule(i) => i
    _ => -1
  }
  inspect(ia, content="0")
  inspect(ib, content="1")
}

///|
test "runtime: relation and rule arrays start empty" {
  let rt = Runtime::Runtime()
  inspect(rt.datalog.relations.length(), content="0")
  inspect(rt.datalog.rules.length(), content="0")
}

///|
test "new_rule: registers rule with input and output relations" {
  let rt = Runtime::Runtime()
  let input : Relation[String] = Relation::Relation(rt)
  let output : Relation[String] = Relation::Relation(rt)
  let rule_id = rt.new_rule([input.id()], [output.id()], () => ())
  inspect(rt.datalog.rules.length(), content="1")
  let _ = rule_id // just check it was created
}

///|
test "panic new_rule: non-relation cell_id in inputs aborts" {
  let rt = Runtime::Runtime()
  let sig = Input::Input(rt, 1)
  rt.new_rule([sig.id()], [], () => ()) |> ignore
}

///|
test "panic new_rule: input relation from another runtime aborts" {
  let rt_a = Runtime::Runtime()
  let rt_b = Runtime::Runtime()
  let input_b : Relation[Int] = Relation::Relation(rt_b)
  let output_a : Relation[Int] = Relation::Relation(rt_a)
  rt_a.new_rule([input_b.id()], [output_a.id()], () => ()) |> ignore
}

///|
test "panic new_rule: output relation from another runtime aborts" {
  let rt_a = Runtime::Runtime()
  let rt_b = Runtime::Runtime()
  let input_a : Relation[Int] = Relation::Relation(rt_a)
  let output_b : Relation[Int] = Relation::Relation(rt_b)
  rt_a.new_rule([input_a.id()], [output_b.id()], () => ()) |> ignore
}

///|
test "new_rule: classifies declaration roles" {
  let rt = Runtime::Runtime()
  let input_only : Relation[Int] = Relation::Relation(rt)
  let output_only : Relation[Int] = Relation::Relation(rt)
  let both : Relation[Int] = Relation::Relation(rt)
  let input_only_rule = rt.new_rule([input_only.id()], [], () => ())
  let output_only_rule = rt.new_rule([], [output_only.id()], () => ())
  let both_rule = rt.new_rule([both.id()], [both.id()], () => ())

  match find_live_rule_declaration(rt.core, rt.datalog.rules, input_only.id()) {
    Some(declaration) => {
      assert_eq(declaration.rule_id, input_only_rule.id)
      assert_true(declaration.role is InputOnly)
    }
    None => abort("expected input declaration")
  }
  match
    find_live_rule_declaration(rt.core, rt.datalog.rules, output_only.id()) {
    Some(declaration) => {
      assert_eq(declaration.rule_id, output_only_rule.id)
      assert_true(declaration.role is OutputOnly)
    }
    None => abort("expected output declaration")
  }
  match find_live_rule_declaration(rt.core, rt.datalog.rules, both.id()) {
    Some(declaration) => {
      assert_eq(declaration.rule_id, both_rule.id)
      assert_true(declaration.role is InputAndOutput)
    }
    None => abort("expected both declaration")
  }
}

///|
test "new_rule: declaration query skips disposed rules in registration order" {
  let rt = Runtime::Runtime()
  let relation : Relation[Int] = Relation::Relation(rt)
  let first = rt.new_rule([relation.id()], [], () => ())
  let second = rt.new_rule([relation.id()], [], () => ())
  rt.dispose_rule(first)
  match find_live_rule_declaration(rt.core, rt.datalog.rules, relation.id()) {
    Some(declaration) => assert_eq(declaration.rule_id, second.id)
    None => abort("expected later live declaration")
  }
  rt.dispose_rule(second)
  assert_true(
    find_live_rule_declaration(rt.core, rt.datalog.rules, relation.id()) is None,
  )
}

///|
test "new_rule: declaration arrays are snapshotted" {
  let rt = Runtime::Runtime()
  let input : Relation[Int] = Relation::Relation(rt)
  let output : Relation[Int] = Relation::Relation(rt)
  let input_ids = [input.id()]
  let output_ids = [output.id()]
  rt.new_rule(input_ids, output_ids, () => ()) |> ignore
  input_ids.clear()
  output_ids.clear()
  assert_eq(rt.datalog.rules[0].input_relations.length(), 1)
  assert_eq(rt.datalog.rules[0].output_relations.length(), 1)
  assert_true(rt.datalog.rules[0].input_relations.contains(input.id()))
  assert_true(rt.datalog.rules[0].output_relations.contains(output.id()))
}

///|
test "panic new_rule: disposed input relation aborts" {
  let rt = Runtime::Runtime()
  let input : Relation[Int] = Relation::Relation(rt)
  input.dispose()
  rt.new_rule([input.id()], [], () => ()) |> ignore
}

///|
test "panic new_rule: disposed output relation aborts" {
  let rt = Runtime::Runtime()
  let output : MapRelation[Int, String] = MapRelation::MapRelation(rt)
  output.dispose()
  rt.new_rule([], [output.id()], () => ()) |> ignore
}

///|
test "relation: iter reads from current (post-fixpoint)" {
  let rt = Runtime::Runtime()
  let rel : Relation[Int] = Relation::Relation(rt)
  let _ = rel.insert(10)
  let _ = rel.insert(20)
  rt.fixpoint()
  let sum = rel.iter().fold(init=0, (acc, x) => acc + x)
  inspect(sum, content="30")
}

///|
test "fixpoint: transitive closure — edge(a,b)+edge(b,c) derives path(a,c)" {
  let rt = Runtime::Runtime()
  let edge : Relation[(String, String)] = Relation::Relation(rt)
  let path : Relation[(String, String)] = Relation::Relation(rt)
  let _ = rt.new_rule([edge.id()], [path.id()], () => {
    // path(x,y) :- edge(x,y)  [only new edges this iteration]
    for e in edge.delta_iter() {
      path.insert(e) |> ignore
    }
    // path(x,z) :- path(x,y), edge(y,z)  [current × current join]
    for p in path.iter() {
      for e in edge.iter() {
        if p.1 == e.0 {
          path.insert((p.0, e.1)) |> ignore
        }
      }
    }
  })
  edge.insert(("a", "b")) |> ignore
  edge.insert(("b", "c")) |> ignore
  rt.fixpoint()
  inspect(path.contains(("a", "b")), content="true")
  inspect(path.contains(("b", "c")), content="true")
  inspect(path.contains(("a", "c")), content="true")
  inspect(path.contains(("a", "a")), content="false")
}

///|
test "fixpoint: semi-naive recursion preserves delta frontier across iterations" {
  let rt = Runtime::Runtime()
  let edge : Relation[(String, String)] = Relation::Relation(rt)
  let path : Relation[(String, String)] = Relation::Relation(rt)
  let _ = rt.new_rule([edge.id(), path.id()], [path.id()], () => {
    for e in edge.delta_iter() {
      path.insert(e) |> ignore
    }
    for p in path.delta_iter() {
      for e in edge.iter() {
        if p.1 == e.0 {
          path.insert((p.0, e.1)) |> ignore
        }
      }
    }
  })
  edge.insert(("a", "b")) |> ignore
  edge.insert(("b", "c")) |> ignore
  edge.insert(("c", "d")) |> ignore
  rt.fixpoint()
  inspect(path.contains(("a", "c")), content="true")
  inspect(path.contains(("b", "d")), content="true")
  inspect(path.contains(("a", "d")), content="true")
}

///|
test "fixpoint: pull memo depending on relation recomputes after fixpoint" {
  let rt = Runtime::Runtime()
  let rel : Relation[Int] = Relation::Relation(rt)
  let m = Derived(rt, () => rel.iter().fold(init=0, (acc, x) => acc + x))
  rel.insert(1) |> ignore
  rel.insert(2) |> ignore
  rt.fixpoint()
  inspect(m.read_or_abort(), content="3")
  rel.insert(3) |> ignore
  rt.fixpoint()
  inspect(m.read_or_abort(), content="6")
}

///|
test "fixpoint: pull memo depending on relation contains recomputes after fixpoint" {
  let rt = Runtime::Runtime()
  let rel : Relation[Int] = Relation::Relation(rt)
  let mut compute_count = 0
  let m = Derived(rt, () => {
    compute_count = compute_count + 1
    rel.contains(1)
  })
  inspect(m.read_or_abort(), content="false")
  inspect(compute_count, content="1")
  rel.insert(1) |> ignore
  rt.fixpoint()
  inspect(m.read_or_abort(), content="true")
  inspect(compute_count, content="2")
}

///|
test "panic fixpoint: Memo::get() inside rule body aborts" {
  let rt = Runtime::Runtime()
  let rel : Relation[Int] = Relation::Relation(rt)
  let m = Derived(rt, () => rel.iter().fold(init=0, (acc, x) => acc + x))
  // Pre-verify the memo so the fast-path would otherwise return stale data
  inspect(m.read_or_abort(), content="0")
  let _ = rt.new_rule([rel.id()], [rel.id()], () => {
    // This must abort — Memo::get() during fixpoint could return stale values
    let _ = m.get_or_abort()
  })
  rel.insert(1) |> ignore
  rt.fixpoint()
}

///|
test "panic fixpoint: Derived::read_or_abort() inside rule body aborts" {
  // The permissive read path also aborts during fixpoint (InFixpoint guard).
  let rt = Runtime::Runtime()
  let rel : Relation[Int] = Relation::Relation(rt)
  let m = Derived(rt, () => rel.iter().fold(init=0, (acc, x) => acc + x))
  inspect(m.read_or_abort(), content="0")
  let _ = rt.new_rule([rel.id()], [rel.id()], () => {
    let _ = m.read_or_abort()
  })
  rel.insert(1) |> ignore
  rt.fixpoint()
}

///|
test "panic fixpoint: HybridMemo::get() inside rule body aborts" {
  let rt = Runtime::Runtime()
  let rel : Relation[Int] = Relation::Relation(rt)
  let h = ReachableDerived(rt, () => {
    rel.iter().fold(init=0, (acc, x) => acc + x)
  })
  inspect(h.read_or_abort(), content="0")
  let _ = rt.new_rule([rel.id()], [rel.id()], () => {
    let _ = h.get()
  })
  rel.insert(1) |> ignore
  rt.fixpoint()
}

///|
test "panic relation: iter cross-runtime read aborts inside memo" {
  let rt_a = Runtime::Runtime()
  let rt_b = Runtime::Runtime()
  let rel_b : Relation[Int] = Relation::Relation(rt_b)
  let memo_a = Derived(rt_a, () => {
    rel_b.iter().fold(init=0, (acc, x) => acc + x)
  })
  let _ = memo_a.read_or_abort()
}

///|
test "panic relation: contains cross-runtime read aborts inside memo" {
  let rt_a = Runtime::Runtime()
  let rt_b = Runtime::Runtime()
  let rel_b : Relation[Int] = Relation::Relation(rt_b)
  let memo_a = Derived(rt_a, () => rel_b.contains(1))
  let _ = memo_a.read_or_abort()
}

///|
test "fixpoint: terminates when no new facts derived" {
  let rt = Runtime::Runtime()
  let rel : Relation[Int] = Relation::Relation(rt)
  let _ = rt.new_rule([rel.id()], [rel.id()], () => ()) // no-op rule
  rel.insert(1) |> ignore
  rt.fixpoint() // must not loop forever
  inspect(rel.contains(1), content="true")
}

///|
test "fixpoint: relation created during rule execution converges in same call" {
  let rt = Runtime::Runtime()
  let seed : Relation[Int] = Relation::Relation(rt)
  let derived_ref : Ref[Relation[Int]?] = { val: None }
  let _ = rt.new_rule([seed.id()], [], () => {
    let derived = match derived_ref.val {
      Some(rel) => rel
      None => {
        let rel : Relation[Int] = Relation::Relation(rt)
        derived_ref.val = Some(rel)
        rel
      }
    }
    for n in seed.delta_iter() {
      derived.insert(n + 1) |> ignore
    }
  })
  seed.insert(1) |> ignore
  rt.fixpoint()
  let derived = match derived_ref.val {
    Some(rel) => rel
    None => abort("expected derived relation to exist")
  }
  inspect(derived.contains(2), content="true")
}

///|
test "panic fixpoint: aborts inside a batch" {
  let rt = Runtime::Runtime()
  let rel : Relation[Int] = Relation::Relation(rt)
  rel.insert(1) |> ignore
  rt.core.batch.depth = 1
  rt.fixpoint()
}

///|
test "get_changed_at: relation changed_at updated by fixpoint" {
  let rt = Runtime::Runtime()
  let rel : Relation[Int] = Relation::Relation(rt)
  let rev_before = rt.core.revision.current_revision
  rel.insert(1) |> ignore
  rt.fixpoint()
  let rel_idx = match rt.core.cell_index[rel.id().id] {
    Relation(i) => i
    _ => abort("")
  }
  inspect(
    rt.datalog.relations[rel_idx].meta.changed_at > rev_before,
    content="true",
  )
}

///|
test "get_changed_at: relation duplicate frontier preserves changed_at" {
  let rt = Runtime::Runtime()
  let rel : Relation[Int] = Relation::Relation(rt)
  rel.insert(1) |> ignore
  rt.fixpoint()
  let changed_at_before = rt.get_changed_at(rel.id())
  let mut memo_count = 0
  let m = Derived(rt, fn() {
    memo_count += 1
    rel.contains(1)
  })
  inspect(m.read_or_abort(), content="true")
  // Inject a duplicate frontier to pin RelationData's net-change check.
  rel.delta.val.add(1)
  rt.fixpoint()
  inspect(rt.get_changed_at(rel.id()) == changed_at_before, content="true")
  inspect(m.read_or_abort(), content="true")
  inspect(memo_count, content="1")
}

///|
/// Regression: publish_cell_changes must run push_propagate_from before
/// fire_on_change so that push nodes downstream of a Relation are recomputed
/// before any on_change callback fires.
test "fixpoint: push EagerDerived downstream of Relation recomputes before on_change" {
  let rt = Runtime::Runtime()
  let rel : Relation[Int] = Relation::Relation(rt)
  // EagerDerived reads the relation's current set; depends on rel's CellId.
  let r = EagerDerived::EagerDerived(rt, () => {
    rel.iter().fold(init=0, (acc, x) => acc + x)
  })
  let _ = read_reactive_for_test(r) // establish dependency
  let mut reactive_val_at_callback = -1
  rt.set_on_change(fn() { reactive_val_at_callback = read_reactive_for_test(r) })
  rel.insert(7) |> ignore
  rt.fixpoint()
  // The reactive must have been recomputed (via push propagation) before
  // on_change fired, so the callback saw the new value.
  inspect(reactive_val_at_callback, content="7")
}

///|
test "fixpoint: disposed relation frontier is skipped" {
  let rt = Runtime::Runtime()
  let rel : Relation[Int] = Relation::Relation(rt)
  rel.dispose()
  rel.delta.val.add(42)
  let changed_ids = @kernel.run_fixpoint(rt.core, rt.datalog)
  assert_false(changed_ids.contains(rel.id()))
  assert_true(rel.delta.val.contains(42))
  assert_false(rel.current.val.contains(42))
}

///|
test "fixpoint: disposed map relation frontier is skipped" {
  let rt = Runtime::Runtime()
  let rel : MapRelation[String, Int] = MapRelation::MapRelation(rt)
  rel.dispose()
  rel.delta.val.set("injected", 42)
  let changed_ids = @kernel.run_fixpoint(rt.core, rt.datalog)
  assert_false(changed_ids.contains(rel.id()))
  assert_true(rel.delta.val.get("injected") is Some(42))
  assert_true(rel.current.val.get("injected") is None)
}
