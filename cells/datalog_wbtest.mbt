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
  let rt = Runtime::new()
  inspect(rt.relations.length(), content="0")
  inspect(rt.rules.length(), content="0")
}

///|
test "relation: insert adds to delta, not current" {
  let rt = Runtime::new()
  let rel : Relation[Int] = Relation::new(rt)
  let inserted = rel.insert(42)
  inspect(inserted, content="true")
  inspect(rel.contains(42), content="false") // not in current yet
}

///|
test "relation: duplicate insert returns false" {
  let rt = Runtime::new()
  let rel : Relation[Int] = Relation::new(rt)
  let _ = rel.insert(1)
  let dup = rel.insert(1)
  inspect(dup, content="false")
}

///|
test "new_rule: registers rule with input and output relations" {
  let rt = Runtime::new()
  let input : Relation[String] = Relation::new(rt)
  let output : Relation[String] = Relation::new(rt)
  let rule_id = rt.new_rule([input.id()], [output.id()], fn() { () })
  inspect(rt.rules.length(), content="1")
  let _ = rule_id // just check it was created
}

///|
test "panic new_rule: non-relation cell_id in inputs aborts" {
  let rt = Runtime::new()
  let sig = Signal::new(rt, 1)
  rt.new_rule([sig.id()], [], fn() { () }) |> ignore
}

///|
test "panic new_rule: input relation from another runtime aborts" {
  let rt_a = Runtime::new()
  let rt_b = Runtime::new()
  let input_b : Relation[Int] = Relation::new(rt_b)
  let output_a : Relation[Int] = Relation::new(rt_a)
  rt_a.new_rule([input_b.id()], [output_a.id()], fn() { () }) |> ignore
}

///|
test "panic new_rule: output relation from another runtime aborts" {
  let rt_a = Runtime::new()
  let rt_b = Runtime::new()
  let input_a : Relation[Int] = Relation::new(rt_a)
  let output_b : Relation[Int] = Relation::new(rt_b)
  rt_a.new_rule([input_a.id()], [output_b.id()], fn() { () }) |> ignore
}

///|
test "relation: iter reads from current (post-fixpoint)" {
  let rt = Runtime::new()
  let rel : Relation[Int] = Relation::new(rt)
  let _ = rel.insert(10)
  let _ = rel.insert(20)
  rt.fixpoint()
  let sum = rel.iter().fold(init=0, fn(acc, x) { acc + x })
  inspect(sum, content="30")
}

///|
test "fixpoint: transitive closure — edge(a,b)+edge(b,c) derives path(a,c)" {
  let rt = Runtime::new()
  let edge : Relation[(String, String)] = Relation::new(rt)
  let path : Relation[(String, String)] = Relation::new(rt)
  let _ = rt.new_rule([edge.id()], [path.id()], fn() {
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
  let rt = Runtime::new()
  let edge : Relation[(String, String)] = Relation::new(rt)
  let path : Relation[(String, String)] = Relation::new(rt)
  let _ = rt.new_rule([edge.id(), path.id()], [path.id()], fn() {
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
  let rt = Runtime::new()
  let rel : Relation[Int] = Relation::new(rt)
  let m = Memo::new(rt, fn() { rel.iter().fold(init=0, fn(acc, x) { acc + x }) })
  rel.insert(1) |> ignore
  rel.insert(2) |> ignore
  rt.fixpoint()
  inspect(m.get(), content="3")
  rel.insert(3) |> ignore
  rt.fixpoint()
  inspect(m.get(), content="6")
}

///|
test "fixpoint: pull memo depending on relation contains recomputes after fixpoint" {
  let rt = Runtime::new()
  let rel : Relation[Int] = Relation::new(rt)
  let mut compute_count = 0
  let m = Memo::new(rt, fn() {
    compute_count = compute_count + 1
    rel.contains(1)
  })
  inspect(m.get(), content="false")
  inspect(compute_count, content="1")
  rel.insert(1) |> ignore
  rt.fixpoint()
  inspect(m.get(), content="true")
  inspect(compute_count, content="2")
}

///|
test "panic relation: iter cross-runtime read aborts inside memo" {
  let rt_a = Runtime::new()
  let rt_b = Runtime::new()
  let rel_b : Relation[Int] = Relation::new(rt_b)
  let memo_a = Memo::new(rt_a, fn() {
    rel_b.iter().fold(init=0, fn(acc, x) { acc + x })
  })
  let _ = memo_a.get()
}

///|
test "panic relation: contains cross-runtime read aborts inside memo" {
  let rt_a = Runtime::new()
  let rt_b = Runtime::new()
  let rel_b : Relation[Int] = Relation::new(rt_b)
  let memo_a = Memo::new(rt_a, fn() { rel_b.contains(1) })
  let _ = memo_a.get()
}

///|
test "fixpoint: terminates when no new facts derived" {
  let rt = Runtime::new()
  let rel : Relation[Int] = Relation::new(rt)
  let _ = rt.new_rule([rel.id()], [rel.id()], fn() { () }) // no-op rule
  rel.insert(1) |> ignore
  rt.fixpoint() // must not loop forever
  inspect(rel.contains(1), content="true")
}

///|
test "get_changed_at: relation changed_at updated by fixpoint" {
  let rt = Runtime::new()
  let rel : Relation[Int] = Relation::new(rt)
  let rev_before = rt.current_revision
  rel.insert(1) |> ignore
  rt.fixpoint()
  let rel_idx = match rt.cell_index[rel.id().id] {
    Relation(i) => i
    _ => abort("")
  }
  inspect(rt.relations[rel_idx].changed_at > rev_before, content="true")
}
