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

///|
test "hybrid memo: basic get() returns correct value" {
  let rt = Runtime::new()
  let s = Signal::new(rt, 1)
  let h = HybridMemo::new(rt, () => s.get() * 2)
  inspect(h.get(), content="2")
  s.set(5)
  inspect(h.get(), content="10")
}

///|
test "hybrid memo: fast path skips compute when not dirtied" {
  let rt = Runtime::new()
  let s = Signal::new(rt, 1)
  let unrelated = Signal::new(rt, 99)
  let mut count = 0
  let h = HybridMemo::new(rt, () => { count = count + 1; s.get() })
  let _ = h.get()
  inspect(count, content="1")
  unrelated.set(100)
  let _ = h.get()
  inspect(count, content="1") // unrelated change → not dirtied → no recompute
}
