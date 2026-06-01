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
test "runtime: hybrid memo does not increment push node_count" {
  let rt = Runtime::Runtime()
  inspect(rt.push.node_count, content="0")
  let s = Signal::Signal(rt, 0)
  let _h = HybridMemo::HybridMemo(rt, fn() { s.get() * 2 })
  inspect(rt.push.node_count, content="0") // hybrid memos don't count as push nodes
}

///|
test "hybrid memo: basic get() returns correct value" {
  let rt = Runtime::Runtime()
  let s = Signal::Signal(rt, 1)
  let h = HybridMemo::HybridMemo(rt, () => s.get() * 2)
  inspect(read_hybrid_for_test(h), content="2")
  s.set(5)
  inspect(read_hybrid_for_test(h), content="10")
}

///|
test "hybrid memo: fast path skips compute when not dirtied" {
  let rt = Runtime::Runtime()
  let s = Signal::Signal(rt, 1)
  let unrelated = Signal::Signal(rt, 99)
  let mut count = 0
  let h = HybridMemo::HybridMemo(rt, () => {
    count = count + 1
    s.get()
  })
  let _ = read_hybrid_for_test(h)
  inspect(count, content="1")
  unrelated.set(100)
  let _ = read_hybrid_for_test(h)
  inspect(count, content="1") // unrelated change → not dirtied → no recompute
}

///|
test "hybrid memo: verified_at staleness triggers recompute on get" {
  let rt = Runtime::Runtime()
  let s = Signal::Signal(rt, 1)
  let h = HybridMemo::HybridMemo(rt, () => s.get() + 10)
  let _ = read_hybrid_for_test(h)
  s.set(5) // bumps revision — verified_at becomes stale
  inspect(read_hybrid_for_test(h), content="15") // stale verified_at triggers recompute
}

///|
test "get_subscribers: HybridMemo arm returns subscribers" {
  let rt = Runtime::Runtime()
  let h = HybridMemo::HybridMemo(rt, () => 42)
  let _ = read_hybrid_for_test(h)
  let subs = rt.get_subscribers(h.id()).collect()
  inspect(subs.length(), content="0") // leaf node, no subscribers yet
}

///|
test "hybrid memo: backdating — unchanged value does not bump changed_at" {
  let rt = Runtime::Runtime()
  let s = Signal::Signal(rt, 1)
  let h = HybridMemo::HybridMemo(rt, () => s.get())
  let _ = read_hybrid_for_test(h)
  let h_idx = match rt.core.cell_index[h.id().id] {
    HybridMemo(i) => i
    _ => abort("")
  }
  let before = rt.pull.memos[h_idx].meta.changed_at
  s.set(1) // same value → signal backdating → h may not be dirtied
  let _ = read_hybrid_for_test(h)
  inspect(rt.pull.memos[h_idx].meta.changed_at == before, content="true")
}

///|
test "hybrid memo: lazy verify after pull-memo backdating leaves HybridMemo up-to-date" {
  let rt = Runtime::Runtime()
  let s = Signal::Signal(rt, 1)
  let mut memo_runs = 0
  let m = Memo::Memo(rt, () => {
    memo_runs = memo_runs + 1
    ignore(s.get())
    1
  })
  let h = HybridMemo::HybridMemo(rt, () => m.get() + 10)
  inspect(read_hybrid_for_test(h), content="11")
  inspect(memo_runs, content="1")
  s.set(2) // m re-verifies and backdates unchanged; h should become clean
  inspect(read_hybrid_for_test(h), content="11")
  inspect(memo_runs, content="2")
  let _ = read_hybrid_for_test(h)
  inspect(memo_runs, content="2")
}

///|
test "hybrid regression: pull memo rechecks stale hybrid deps" {
  let rt = Runtime::Runtime()
  let s = Signal::Signal(rt, 1)
  let h = HybridMemo::HybridMemo(rt, () => s.get() * 2)
  let m = Memo::Memo(rt, () => h.get() + 1)
  inspect(read_memo_for_test(m), content="3")
  s.set(3)
  inspect(read_memo_for_test(m), content="7")
}

///|
test "hybrid regression: nested hybrid verification rechecks upstream hybrid" {
  let rt = Runtime::Runtime()
  let s = Signal::Signal(rt, 1)
  let h1 = HybridMemo::HybridMemo(rt, () => s.get() + 1)
  let h2 = HybridMemo::HybridMemo(rt, () => h1.get() * 10)
  inspect(read_hybrid_for_test(h2), content="20")
  s.set(2)
  inspect(read_hybrid_for_test(h2), content="30")
}

///|
test "hybrid regression: push propagation traverses hybrid to reactive" {
  let rt = Runtime::Runtime()
  let s = Signal::Signal(rt, 1)
  let h = HybridMemo::HybridMemo(rt, () => s.get() * 2)
  let mut recomputes = 0
  let r = Reactive::new(rt, () => {
    recomputes = recomputes + 1
    h.get() + 1
  })
  inspect(r.read_permissive(), content="3")
  inspect(recomputes, content="1")
  s.set(5)
  inspect(recomputes, content="2")
  inspect(r.read_permissive(), content="11")
}

///|
test "hybrid memo: dispose removes from upstream subscriber sets and marks Disposed" {
  let rt = Runtime::Runtime()
  let s = Signal::Signal(rt, 1)
  let h = HybridMemo::HybridMemo(rt, () => s.get() * 2)
  let _ = read_hybrid_for_test(h)
  let subs_before = rt.get_subscribers(s.id()).collect()
  inspect(subs_before.length(), content="1")
  h.dispose()
  let subs_after = rt.get_subscribers(s.id()).collect()
  inspect(subs_after.length(), content="0")
  let is_disposed = match rt.core.cell_index[h.id().id] {
    Disposed => true
    _ => false
  }
  inspect(is_disposed, content="true")
}

///|
test "hybrid memo: dispose is idempotent" {
  let rt = Runtime::Runtime()
  let s = Signal::Signal(rt, 1)
  let h = HybridMemo::HybridMemo(rt, () => s.get())
  let _ = read_hybrid_for_test(h)
  h.dispose()
  h.dispose()
  let subs = rt.get_subscribers(s.id()).collect()
  inspect(subs.length(), content="0")
}

///|
test "panic hybrid verify: disposed dependency aborts verification" {
  let rt = Runtime::Runtime()
  let sig = Signal::Signal(rt, 1)
  let unrelated = Signal::Signal(rt, 0)
  let r = Reactive::new(rt, () => sig.get() * 2)
  let h = HybridMemo::HybridMemo(rt, () => r.get() + 1)
  inspect(read_hybrid_for_test(h), content="3")
  r.dispose()
  unrelated.set(1) // bump revision so hybrid verify path runs again
  let _ = read_hybrid_for_test(h)
}

///|
test "panic hybrid: cross-runtime get aborts" {
  let rt_a = Runtime::Runtime()
  let rt_b = Runtime::Runtime()
  let s_b = Signal::Signal(rt_b, 10)
  let h_b = HybridMemo::HybridMemo(rt_b, () => s_b.get())
  // memo_a computes on rt_a but reads h_b from rt_b → cross-runtime abort
  let memo_a = Memo::Memo(rt_a, () => h_b.get())
  let _ = read_memo_for_test(memo_a)
}

///|
test "panic hybrid: self-referential cycle aborts" {
  // A HybridMemo that reads itself triggers cycle detection via in_progress.
  let rt = Runtime::Runtime()
  // Use a ref cell to close over h before h is created
  let h_ref : Ref[HybridMemo[Int]?] = { val: None }
  let h = HybridMemo::HybridMemo(rt, () => {
    match h_ref.val {
      None => 0
      Some(h) => h.get() + 1 // self-read → cycle
    }
  })
  h_ref.val = Some(h)
  let _ = read_hybrid_for_test(h) // first get: h_ref.val is Some → triggers self-read → abort
}

///|
test "panic hybrid cycle: mixed Memo → HybridMemo → Memo cycle aborts" {
  // Memo m reads HybridMemo h; h reads m → cycle across cell types.
  let rt = Runtime::Runtime()
  let m_ref : Ref[Memo[Int]?] = { val: None }
  let h = HybridMemo::HybridMemo(rt, () => {
    match m_ref.val {
      None => 0
      Some(m) => m.get() + 1 // h reads m → cycle
    }
  })
  let m = Memo::Memo(rt, () => h.get() + 1) // m reads h
  m_ref.val = Some(m)
  let _ = read_memo_for_test(m) // triggers cycle: m → h → m → abort
}
