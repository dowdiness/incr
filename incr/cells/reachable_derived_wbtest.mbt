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
  let s = Input::Input(rt, 0)
  let _rd = ReachableDerived(rt, fn() { s.get() * 2 })
  inspect(rt.push.node_count, content="0") // hybrid memos don't count as push nodes
}

///|
test "hybrid memo: basic get() returns correct value" {
  let rt = Runtime::Runtime()
  let s = Input::Input(rt, 1)
  let rd = ReachableDerived(rt, () => s.get() * 2)
  inspect(rd.read_or_abort(), content="2")
  s.set(5)
  inspect(rd.read_or_abort(), content="10")
}

///|
test "hybrid memo: fast path skips compute when not dirtied" {
  let rt = Runtime::Runtime()
  let s = Input::Input(rt, 1)
  let unrelated = Input::Input(rt, 99)
  let mut count = 0
  let rd = ReachableDerived(rt, () => {
    count = count + 1
    s.get()
  })
  let _ = rd.read_or_abort()
  inspect(count, content="1")
  unrelated.set(100)
  let _ = rd.read_or_abort()
  inspect(count, content="1") // unrelated change → not dirtied → no recompute
}

///|
test "hybrid memo: verified_at staleness triggers recompute on get" {
  let rt = Runtime::Runtime()
  let s = Input::Input(rt, 1)
  let rd = ReachableDerived(rt, () => s.get() + 10)
  let _ = rd.read_or_abort()
  s.set(5) // bumps revision — verified_at becomes stale
  inspect(rd.read_or_abort(), content="15") // stale verified_at triggers recompute
}

///|
test "get_subscribers: HybridMemo arm returns subscribers" {
  let rt = Runtime::Runtime()
  let rd = ReachableDerived(rt, () => 42)
  let _ = rd.read_or_abort()
  let subs = rt.get_subscribers(rd.id()).collect()
  inspect(subs.length(), content="0") // leaf node, no subscribers yet
}

///|
test "hybrid memo: backdating — unchanged value does not bump changed_at" {
  let rt = Runtime::Runtime()
  let s = Input::Input(rt, 1)
  let rd = ReachableDerived(rt, () => s.get())
  let _ = rd.read_or_abort()
  let rd_idx = match rt.core.cell_index[rd.id().id] {
    HybridMemo(i) => i
    _ => abort("")
  }
  let before = rt.pull.memos[rd_idx].meta.changed_at
  s.set(1) // same value → input backdating → h may not be dirtied
  let _ = rd.read_or_abort()
  inspect(rt.pull.memos[rd_idx].meta.changed_at == before, content="true")
}

///|
test "hybrid memo: lazy verify after pull-memo backdating leaves HybridMemo up-to-date" {
  let rt = Runtime::Runtime()
  let s = Input::Input(rt, 1)
  let mut memo_runs = 0
  let m = Derived(rt, () => {
    memo_runs = memo_runs + 1
    ignore(s.get())
    1
  })
  let rd = ReachableDerived(rt, () => m.get_or_abort() + 10)
  inspect(rd.read_or_abort(), content="11")
  inspect(memo_runs, content="1")
  s.set(2) // m re-verifies and backdates unchanged; h should become clean
  inspect(rd.read_or_abort(), content="11")
  inspect(memo_runs, content="2")
  let _ = rd.read_or_abort()
  inspect(memo_runs, content="2")
}

///|
test "hybrid regression: pull memo rechecks stale hybrid deps" {
  let rt = Runtime::Runtime()
  let s = Input::Input(rt, 1)
  let rd = ReachableDerived(rt, () => s.get() * 2)
  let m = Derived(rt, () => rd.get_or_abort() + 1)
  inspect(m.read_or_abort(), content="3")
  s.set(3)
  inspect(m.read_or_abort(), content="7")
}

///|
test "hybrid regression: nested hybrid verification rechecks upstream hybrid" {
  let rt = Runtime::Runtime()
  let s = Input::Input(rt, 1)
  let rd1 = ReachableDerived(rt, () => s.get() + 1)
  let rd2 = ReachableDerived(rt, () => rd1.get_or_abort() * 10)
  inspect(rd2.read_or_abort(), content="20")
  s.set(2)
  inspect(rd2.read_or_abort(), content="30")
}

///|
test "hybrid regression: push propagation traverses hybrid to reactive" {
  let rt = Runtime::Runtime()
  let s = Input::Input(rt, 1)
  let rd = ReachableDerived(rt, () => s.get() * 2)
  let mut recomputes = 0
  let r = EagerDerived::EagerDerived(rt, () => {
    recomputes = recomputes + 1
    rd.get_or_abort() + 1
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
  let s = Input::Input(rt, 1)
  let rd = ReachableDerived(rt, () => s.get() * 2)
  let _ = rd.read_or_abort()
  let subs_before = rt.get_subscribers(s.id()).collect()
  inspect(subs_before.length(), content="1")
  rd.dispose()
  let subs_after = rt.get_subscribers(s.id()).collect()
  inspect(subs_after.length(), content="0")
  let is_disposed = match rt.core.cell_index[rd.id().id] {
    Disposed => true
    _ => false
  }
  inspect(is_disposed, content="true")
}

///|
test "hybrid memo: dispose is idempotent" {
  let rt = Runtime::Runtime()
  let s = Input::Input(rt, 1)
  let rd = ReachableDerived(rt, () => s.get())
  let _ = rd.read_or_abort()
  rd.dispose()
  rd.dispose()
  let subs = rt.get_subscribers(s.id()).collect()
  inspect(subs.length(), content="0")
}

///|
test "panic hybrid verify: disposed dependency aborts verification" {
  let rt = Runtime::Runtime()
  let sig = Input::Input(rt, 1)
  let unrelated = Input::Input(rt, 0)
  let r = EagerDerived::EagerDerived(rt, () => sig.get() * 2)
  let rd = ReachableDerived(rt, () => r.get() + 1)
  inspect(rd.read_or_abort(), content="3")
  r.dispose()
  unrelated.set(1) // bump revision so hybrid verify path runs again
  let _ = rd.read_or_abort()
}

///|
test "panic hybrid: cross-runtime get aborts" {
  let rt_a = Runtime::Runtime()
  let rt_b = Runtime::Runtime()
  let s_b = Input::Input(rt_b, 10)
  let rd_b = ReachableDerived(rt_b, () => s_b.get())
  // d_a computes on rt_a but reads rd_b from rt_b → cross-runtime abort
  let d_a = Derived(rt_a, () => rd_b.get_or_abort())
  let _ = d_a.read_or_abort()
}

///|
test "panic hybrid: self-referential cycle aborts" {
  // A HybridMemo that reads itself triggers cycle detection via in_progress.
  let rt = Runtime::Runtime()
  // Use a ref cell to close over h before h is created
  let rd_ref : Ref[ReachableDerived[Int]?] = { val: None }
  let rd = ReachableDerived(rt, () => {
    match rd_ref.val {
      None => 0
      Some(rd) => rd.get_or_abort() + 1 // self-read → cycle
    }
  })
  rd_ref.val = Some(rd)
  let _ = rd.read_or_abort() // first get: rd_ref.val is Some → triggers self-read → abort
}

///|
test "panic hybrid cycle: mixed Memo → HybridMemo → Memo cycle aborts" {
  // Memo m reads HybridMemo h; h reads m → cycle across cell types.
  let rt = Runtime::Runtime()
  let d_ref : Ref[Derived[Int]?] = { val: None }
  let rd = ReachableDerived(rt, () => {
    match d_ref.val {
      None => 0
      Some(m) => m.get_or_abort() + 1 // rd reads m → cycle
    }
  })
  let m = Derived(rt, () => rd.get_or_abort() + 1) // m reads rd
  d_ref.val = Some(m)
  let _ = m.read_or_abort() // triggers cycle: m → rd → m → abort
}
