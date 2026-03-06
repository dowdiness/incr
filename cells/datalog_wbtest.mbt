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
