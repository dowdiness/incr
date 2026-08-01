///|
test "gc: watch → input.set → watch.read_or_abort sees update" {
  let rt = @incr.Runtime()
  let sig = @incr.Input(rt, 10)
  let m = @incr.Derived(rt, fn() { sig.get() * 2 })
  let watch = m.watch()
  inspect(watch.read_or_abort(), content="20")
  sig.set(15)
  inspect(watch.read_or_abort(), content="30")
  watch.dispose()
}

///|
test "gc: scope dispose + gc sweeps orphaned interior cells" {
  let rt = @incr.Runtime()
  let sig = @incr.Input(rt, 1)
  let scope = @incr.Scope::new(rt)
  let m = scope.derived(fn() { sig.get() + 1 })
  let watch = m.watch()
  ignore(watch.read_or_abort())

  // Create another memo not watched
  let m_orphan = @incr.Derived(rt, fn() { sig.get() + 2 })
  ignore(read_derived_for_test(m_orphan))

  watch.dispose()
  scope.dispose()
  rt.gc()
  assert_true(m.is_disposed()) // disposed by scope
  assert_true(m_orphan.is_disposed()) // swept by gc
}

///|
test "gc: Runtime::read does not leak gc roots" {
  let rt = @incr.Runtime()
  let sig = @incr.Input(rt, 5)
  let m = @incr.Derived(rt, fn() { sig.get() * 3 })
  let val = read_derived_for_test(m)
  inspect(val, content="15")
  // After read, no gc roots should remain for m
  rt.gc()
  assert_true(m.is_disposed())
}

///|
test "gc: manual dispose of watched cell then gc" {
  let rt = @incr.Runtime()
  let sig = @incr.Input(rt, 1)
  let m = @incr.Derived(rt, fn() { sig.get() })
  let watch = m.watch()
  ignore(watch.read_or_abort())
  rt.dispose_cell(m.id())
  watch.dispose() // safe — skips on_unobserve for dead cell
  rt.gc() // safe — m already disposed
}

///|
test "gc: hybrid memo reachable through watch" {
  let rt = @incr.Runtime()
  let sig = @incr.Input(rt, 1)
  let h = @incr.ReachableDerived(rt, fn() { sig.get() + 10 })
  let watch = h.watch()
  inspect(watch.read_or_abort(), content="11")
  rt.gc()
  assert_false(h.is_disposed())
  watch.dispose()
  rt.gc()
  assert_true(h.is_disposed())
}

///|
test "gc: reactive reachable through watch" {
  let rt = @incr.Runtime()
  let sig = @incr.Input(rt, 1)
  let r = @incr.EagerDerived::EagerDerived(rt, fn() { sig.get() * 4 })
  let watch = r.watch()
  inspect(watch.read_or_abort(), content="4")
  rt.gc()
  assert_false(r.is_disposed())
  watch.dispose()
  rt.gc()
  assert_true(r.is_disposed())
}
