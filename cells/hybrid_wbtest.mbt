///|
test "cell_ref: HybridMemo variant pattern-matches correctly" {
  let a : CellRef = CellRef::HybridMemo(4)
  let ia = match a { HybridMemo(i) => i; _ => -1 }
  inspect(ia, content="4")
}
