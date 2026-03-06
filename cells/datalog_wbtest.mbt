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
  let rule_id = rt.new_rule(
    [input.id()],
    [output.id()],
    fn() { () },
  )
  inspect(rt.rules.length(), content="1")
  let _ = rule_id // just check it was created
}

///|
test "panic new_rule: non-relation cell_id in inputs aborts" {
  let rt = Runtime::new()
  let sig = Signal::new(rt, 1)
  rt.new_rule([sig.id()], [], fn() { () }) |> ignore
}
