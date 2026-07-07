///|
test "cell_ref: PullInput and PullMemo variants pattern-match correctly" {
  let a : CellRef = CellRef::PullInput(0)
  let b : CellRef = CellRef::PullMemo(3)
  let ia = match a {
    PullInput(i) => i
    _ => -1
  }
  let ib = match b {
    PullMemo(i) => i
    _ => -1
  }
  inspect(ia, content="0")
  inspect(ib, content="3")
}
