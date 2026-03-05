///|
test "cell_ref: HybridMemo variant pattern-matches correctly" {
  let a : CellRef = CellRef::HybridMemo(4)
  let ia = match a { HybridMemo(i) => i; _ => -1 }
  inspect(ia, content="4")
}

///|
test "runtime: hybrid_memos and hybrid_dirty start empty" {
  let rt = Runtime::new()
  inspect(rt.hybrid_memos.length(), content="0")
  inspect(rt.hybrid_dirty.length(), content="0")
}
