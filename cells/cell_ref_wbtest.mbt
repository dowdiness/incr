///|
test "cell_ref: PullSignal and PullMemo variants pattern-match correctly" {
  let a : CellRef = CellRef::PullSignal(0)
  let b : CellRef = CellRef::PullMemo(3)
  let ia = match a { PullSignal(i) => i; _ => -1 }
  let ib = match b { PullMemo(i) => i; _ => -1 }
  inspect(ia, content="0")
  inspect(ib, content="3")
}
