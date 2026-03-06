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
