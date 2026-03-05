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

///|
test "hybrid memo: dirty flag set by push propagation before get()" {
  let rt = Runtime::new()
  let s = Signal::new(rt, 1)
  let h = HybridMemo::new(rt, () => s.get())
  let _ = h.get()
  s.set(2)
  // After s.set(), push propagation should have set h.dirty = true
  let h_idx = match rt.cell_index[h.id().id] {
    HybridMemo(i) => i
    _ => abort("")
  }
  inspect(rt.hybrid_memos[h_idx].dirty, content="true")
}

///|
test "hybrid memo: dirty flag triggers recompute on get" {
  let rt = Runtime::new()
  let s = Signal::new(rt, 1)
  let h = HybridMemo::new(rt, () => s.get() + 10)
  let _ = h.get()
  s.set(5) // push propagation sets h.dirty = true
  let h_idx = match rt.cell_index[h.id().id] {
    HybridMemo(i) => i
    _ => abort("")
  }
  inspect(rt.hybrid_memos[h_idx].dirty, content="true")
  inspect(h.get(), content="15") // triggers recompute; dirty cleared
  inspect(rt.hybrid_memos[h_idx].dirty, content="false")
}

///|
test "get_subscribers: HybridMemo arm returns subscribers" {
  let rt = Runtime::new()
  let h = HybridMemo::new(rt, () => 42)
  let _ = h.get()
  let subs = rt.get_subscribers(h.id()).collect()
  inspect(subs.length(), content="0") // leaf node, no subscribers yet
}

///|
test "hybrid memo: backdating — unchanged value does not bump changed_at" {
  let rt = Runtime::new()
  let s = Signal::new(rt, 1)
  let h = HybridMemo::new(rt, () => s.get())
  let _ = h.get()
  let h_idx = match rt.cell_index[h.id().id] {
    HybridMemo(i) => i
    _ => abort("")
  }
  let before = rt.hybrid_memos[h_idx].changed_at
  s.set(1) // same value → signal backdating → h may not be dirtied
  let _ = h.get()
  inspect(rt.hybrid_memos[h_idx].changed_at == before, content="true")
}
