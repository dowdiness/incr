///|
test "gc: observe → signal.set → observer.get sees update" {
  let rt = @incr.Runtime()
  let sig = @incr.Signal(rt, 10)
  let m = @incr.Memo(rt, fn() { sig.get() * 2 })
  let obs = m.observe()
  inspect(obs.get(), content="20")
  sig.set(15)
  inspect(obs.get(), content="30")
  obs.dispose()
}

///|
test "gc: scope dispose + gc sweeps orphaned interior cells" {
  let rt = @incr.Runtime()
  let sig = @incr.Signal(rt, 1)
  let scope = @incr.Scope::new(rt)
  let m = scope.memo(fn() { sig.get() + 1 })
  let obs = m.observe()
  ignore(obs.get())

  // Create another memo not observed
  let m_orphan = @incr.Memo(rt, fn() { sig.get() + 2 })
  ignore(m_orphan.get())

  obs.dispose()
  scope.dispose()
  rt.gc()
  assert_true(m.is_disposed()) // disposed by scope
  assert_true(m_orphan.is_disposed()) // swept by gc
}

///|
test "gc: Runtime::read does not leak gc roots" {
  let rt = @incr.Runtime()
  let sig = @incr.Signal(rt, 5)
  let m = @incr.Memo(rt, fn() { sig.get() * 3 })
  let val = rt.read(m)
  inspect(val, content="15")
  // After read, no gc roots should remain for m
  rt.gc()
  assert_true(m.is_disposed())
}

///|
test "gc: manual dispose of observed cell then gc" {
  let rt = @incr.Runtime()
  let sig = @incr.Signal(rt, 1)
  let m = @incr.Memo(rt, fn() { sig.get() })
  let obs = m.observe()
  ignore(obs.get())
  m.dispose()
  obs.dispose() // safe — skips on_unobserve for dead cell
  rt.gc() // safe — m already disposed
}

///|
test "gc: hybrid memo reachable through observer" {
  let rt = @incr.Runtime()
  let sig = @incr.Signal(rt, 1)
  let h = @incr.HybridMemo(rt, fn() { sig.get() + 10 })
  let obs = h.observe()
  inspect(obs.get(), content="11")
  rt.gc()
  assert_false(h.is_disposed())
  obs.dispose()
  rt.gc()
  assert_true(h.is_disposed())
}

///|
test "gc: reactive reachable through observer" {
  let rt = @incr.Runtime()
  let sig = @incr.Signal(rt, 1)
  let r = @incr.Reactive::new(rt, fn() { sig.get() * 4 })
  let obs = r.observe()
  inspect(obs.get(), content="4")
  rt.gc()
  assert_false(r.is_disposed())
  obs.dispose()
  rt.gc()
  assert_true(r.is_disposed())
}
