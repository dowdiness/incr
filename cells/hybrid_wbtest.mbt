///|
test "cell_ref: HybridMemo variant pattern-matches correctly" {
  let a : CellRef = CellRef::HybridMemo(4)
  let ia = match a {
    HybridMemo(i) => i
    _ => -1
  }
  inspect(ia, content="4")
}

///|
test "runtime: hybrid_dirty starts empty" {
  let rt = Runtime::new()
  inspect(rt.push.hybrid_dirty.length(), content="0")
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
  let h = HybridMemo::new(rt, () => {
    count = count + 1
    s.get()
  })
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
  let h_idx = match rt.core.cell_index[h.id().id] {
    HybridMemo(i) => i
    _ => abort("")
  }
  inspect(rt.pull.memos[h_idx].dirty, content="true")
}

///|
test "hybrid memo: dirty flag triggers recompute on get" {
  let rt = Runtime::new()
  let s = Signal::new(rt, 1)
  let h = HybridMemo::new(rt, () => s.get() + 10)
  let _ = h.get()
  s.set(5) // push propagation sets h.dirty = true
  let h_idx = match rt.core.cell_index[h.id().id] {
    HybridMemo(i) => i
    _ => abort("")
  }
  inspect(rt.pull.memos[h_idx].dirty, content="true")
  inspect(h.get(), content="15") // triggers recompute; dirty cleared
  inspect(rt.pull.memos[h_idx].dirty, content="false")
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
  let h_idx = match rt.core.cell_index[h.id().id] {
    HybridMemo(i) => i
    _ => abort("")
  }
  let before = rt.pull.memos[h_idx].changed_at
  s.set(1) // same value → signal backdating → h may not be dirtied
  let _ = h.get()
  inspect(rt.pull.memos[h_idx].changed_at == before, content="true")
}

///|
test "hybrid memo: clean verify clears dirty after pull-memo backdating" {
  let rt = Runtime::new()
  let s = Signal::new(rt, 1)
  let mut memo_runs = 0
  let m = Memo::new(rt, () => {
    memo_runs = memo_runs + 1
    ignore(s.get())
    1
  })
  let h = HybridMemo::new(rt, () => m.get() + 10)
  inspect(h.get(), content="11")
  inspect(memo_runs, content="1")
  let h_idx = match rt.core.cell_index[h.id().id] {
    HybridMemo(i) => i
    _ => abort("")
  }
  s.set(2) // m re-verifies and backdates unchanged; h should become clean
  inspect(rt.pull.memos[h_idx].dirty, content="true")
  inspect(h.get(), content="11")
  inspect(memo_runs, content="2")
  inspect(rt.pull.memos[h_idx].dirty, content="false")
  let _ = h.get()
  inspect(memo_runs, content="2")
}

///|
test "hybrid regression: pull memo rechecks dirty hybrid deps" {
  let rt = Runtime::new()
  let s = Signal::new(rt, 1)
  let h = HybridMemo::new(rt, () => s.get() * 2)
  let m = Memo::new(rt, () => h.get() + 1)
  inspect(m.get(), content="3")
  s.set(3)
  inspect(m.get(), content="7")
}

///|
test "hybrid regression: nested hybrid verification rechecks upstream hybrid" {
  let rt = Runtime::new()
  let s = Signal::new(rt, 1)
  let h1 = HybridMemo::new(rt, () => s.get() + 1)
  let h2 = HybridMemo::new(rt, () => h1.get() * 10)
  inspect(h2.get(), content="20")
  s.set(2)
  inspect(h2.get(), content="30")
}

///|
test "hybrid regression: push propagation traverses hybrid to reactive" {
  let rt = Runtime::new()
  let s = Signal::new(rt, 1)
  let h = HybridMemo::new(rt, () => s.get() * 2)
  let mut recomputes = 0
  let r = Reactive::new(rt, () => {
    recomputes = recomputes + 1
    h.get() + 1
  })
  inspect(r.get(), content="3")
  inspect(recomputes, content="1")
  s.set(5)
  inspect(recomputes, content="2")
  inspect(r.get(), content="11")
}

///|
test "panic hybrid verify: disposed dependency aborts verification" {
  let rt = Runtime::new()
  let sig = Signal::new(rt, 1)
  let unrelated = Signal::new(rt, 0)
  let r = Reactive::new(rt, () => sig.get() * 2)
  let h = HybridMemo::new(rt, () => r.get() + 1)
  inspect(h.get(), content="3")
  r.dispose()
  unrelated.set(1) // bump revision so hybrid verify path runs again
  let _ = h.get()
}

///|
test "panic hybrid: cross-runtime get aborts" {
  let rt_a = Runtime::new()
  let rt_b = Runtime::new()
  let s_b = Signal::new(rt_b, 10)
  let h_b = HybridMemo::new(rt_b, () => s_b.get())
  // memo_a computes on rt_a but reads h_b from rt_b → cross-runtime abort
  let memo_a = Memo::new(rt_a, () => h_b.get())
  let _ = memo_a.get()
}

///|
test "panic hybrid: self-referential cycle aborts" {
  // A HybridMemo that reads itself triggers cycle detection via in_progress.
  let rt = Runtime::new()
  // Use a ref cell to close over h before h is created
  let h_ref : Ref[HybridMemo[Int]?] = { val: None }
  let h = HybridMemo::new(rt, () => {
    match h_ref.val {
      None => 0
      Some(h) => h.get() + 1 // self-read → cycle
    }
  })
  h_ref.val = Some(h)
  let _ = h.get() // first get: h_ref.val is Some → triggers self-read → abort
}

///|
test "panic hybrid cycle: mixed Memo → HybridMemo → Memo cycle aborts" {
  // Memo m reads HybridMemo h; h reads m → cycle across cell types.
  let rt = Runtime::new()
  let m_ref : Ref[Memo[Int]?] = { val: None }
  let h = HybridMemo::new(rt, () => {
    match m_ref.val {
      None => 0
      Some(m) => m.get() + 1 // h reads m → cycle
    }
  })
  let m = Memo::new(rt, () => h.get() + 1) // m reads h
  m_ref.val = Some(m)
  let _ = m.get() // triggers cycle: m → h → m → abort
}
