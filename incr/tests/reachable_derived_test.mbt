///|
test "hybrid: basic get and update" {
  let rt = Runtime::Runtime()
  let s = Signal::Signal(rt, 1)
  let h = @incr.ReachableDerived::ReachableDerived(rt, () => s.get() * 2)
  inspect(read_reachable_for_test(h), content="2")
  s.set(5)
  inspect(read_reachable_for_test(h), content="10")
}

///|
test "hybrid: create_hybrid_memo helper" {
  let db = TestDb()
  let s = @incr.create_signal(db, 3)
  let h = @incr.create_reachable_derived(db, () => s.get() + 1)
  inspect(read_reachable_for_test(h), content="4")
  s.set(10)
  inspect(read_reachable_for_test(h), content="11")
}

///|
test "hybrid: is_up_to_date before first get returns false" {
  let rt = Runtime::Runtime()
  let s = Signal::Signal(rt, 1)
  let h = @incr.ReachableDerived::ReachableDerived(rt, () => s.get())
  // Never-computed memo has no cached value — must not be considered up-to-date.
  inspect(h.is_fresh(), content="false")
}

///|
test "hybrid: is_up_to_date via Readable" {
  let rt = Runtime::Runtime()
  let s = Signal::Signal(rt, 1)
  let h = @incr.ReachableDerived::ReachableDerived(rt, () => s.get())
  let _ = read_reachable_for_test(h)
  inspect(h.is_fresh(), content="true")
  s.set(2)
  inspect(h.is_fresh(), content="false")
  let _ = read_reachable_for_test(h)
  inspect(h.is_fresh(), content="true")
}

///|
test "hybrid: unchanged value does not propagate (backdating)" {
  // If the hybrid memo recomputes to the same value, downstream memos skip.
  let rt = Runtime::Runtime()
  let s = Signal::Signal(rt, 2)
  let h = @incr.ReachableDerived::ReachableDerived(rt, () => s.get() % 2) // always 0
  let mut count = 0
  let m = Derived::Derived(rt, () => {
    count = count + 1
    h.get_or_abort() + 1
  })
  inspect(read_derived_for_test(m), content="1")
  inspect(count, content="1")
  s.set(4) // h still computes 0 → backdated → m should not recompute
  inspect(read_derived_for_test(m), content="1")
  inspect(count, content="1") // no recompute
}

///|
test "hybrid: diamond — signal → two hybrids → memo" {
  let rt = Runtime::Runtime()
  let s = Signal::Signal(rt, 3)
  let h1 = @incr.ReachableDerived::ReachableDerived(rt, () => s.get() + 1)
  let h2 = @incr.ReachableDerived::ReachableDerived(rt, () => s.get() * 2)
  let mut count = 0
  let m = Derived::Derived(rt, () => {
    count = count + 1
    h1.get_or_abort() + h2.get_or_abort()
  })
  inspect(read_derived_for_test(m), content="10") // (3+1) + (3*2) = 4 + 6 = 10
  inspect(count, content="1")
  s.set(5)
  inspect(read_derived_for_test(m), content="16") // (5+1) + (5*2) = 6 + 10 = 16
  inspect(count, content="2")
}

///|
test "hybrid: batch update — single revision" {
  let rt = Runtime::Runtime()
  let x = Signal::Signal(rt, 1)
  let y = Signal::Signal(rt, 2)
  let mut count = 0
  let h = @incr.ReachableDerived::ReachableDerived(rt, () => {
    count = count + 1
    x.get() + y.get()
  })
  inspect(read_reachable_for_test(h), content="3")
  inspect(count, content="1")
  rt.batch(fn() {
    x.set(10)
    y.set(20)
  })
  inspect(read_reachable_for_test(h), content="30")
  inspect(count, content="2") // only one recompute despite two signal changes
}

///|
test "hybrid: chained hybrids" {
  let rt = Runtime::Runtime()
  let s = Signal::Signal(rt, 1)
  let h1 = @incr.ReachableDerived::ReachableDerived(rt, () => s.get() + 1)
  let h2 = @incr.ReachableDerived::ReachableDerived(rt, () => h1.get_or_abort() * 10)
  inspect(read_reachable_for_test(h2), content="20")
  s.set(2)
  inspect(read_reachable_for_test(h2), content="30")
}

///|
test "hybrid: hybrid as dep of memo — pull chain" {
  let rt = Runtime::Runtime()
  let s = Signal::Signal(rt, 1)
  let h = @incr.ReachableDerived::ReachableDerived(rt, () => s.get() * 2)
  let mut count = 0
  let m = Derived::Derived(rt, () => {
    count = count + 1
    h.get_or_abort() + 1
  })
  inspect(read_derived_for_test(m), content="3")
  inspect(count, content="1")
  s.set(3)
  inspect(read_derived_for_test(m), content="7")
  inspect(count, content="2")
}
