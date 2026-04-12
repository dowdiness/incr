///|
test "gc: disposes all unobserved interior cells" {
  let rt = Runtime::new()
  let sig = Signal::new(rt, 1)
  let m = Memo::new(rt, fn() { sig.get() * 2 })
  ignore(m.get())
  rt.gc()
  assert_true(m.is_disposed())
  // Source is never collected
  assert_false(sig.is_disposed())
}

///|
test "gc: keeps observed memo alive" {
  let rt = Runtime::new()
  let sig = Signal::new(rt, 1)
  let m = Memo::new(rt, fn() { sig.get() * 2 })
  let obs = m.observe()
  ignore(obs.get())
  rt.gc()
  assert_false(m.is_disposed())
  inspect(obs.get(), content="2")
  obs.dispose()
}

///|
test "gc: keeps transitive deps of observed memo alive" {
  let rt = Runtime::new()
  let sig = Signal::new(rt, 1)
  let m1 = Memo::new(rt, fn() { sig.get() + 1 })
  let m2 = Memo::new(rt, fn() { m1.get() * 2 })
  let obs = m2.observe()
  ignore(obs.get())
  rt.gc()
  assert_false(m1.is_disposed())
  assert_false(m2.is_disposed())
  obs.dispose()
}

///|
test "gc: disposes unreachable memo in diamond" {
  let rt = Runtime::new()
  let sig = Signal::new(rt, 1)
  let m_used = Memo::new(rt, fn() { sig.get() + 1 })
  let m_unused = Memo::new(rt, fn() { sig.get() + 2 })
  let m_top = Memo::new(rt, fn() { m_used.get() })
  let obs = m_top.observe()
  ignore(obs.get())
  ignore(m_unused.get()) // compute to establish deps, but not observed
  rt.gc()
  assert_false(m_used.is_disposed())
  assert_false(m_top.is_disposed())
  assert_true(m_unused.is_disposed()) // unreachable from any root
  obs.dispose()
}

///|
test "gc: after observer dispose sweeps newly-unreachable" {
  let rt = Runtime::new()
  let sig = Signal::new(rt, 1)
  let m = Memo::new(rt, fn() { sig.get() })
  let obs = m.observe()
  ignore(obs.get())
  obs.dispose()
  rt.gc()
  assert_true(m.is_disposed())
}

///|
test "gc: keeps effects alive as implicit roots" {
  let rt = Runtime::new()
  let sig = Signal::new(rt, 1)
  let m = Memo::new(rt, fn() { sig.get() })
  let log : Ref[Int] = { val: 0 }
  let _eff = Effect::new(rt, fn() { log.val = m.get() })
  rt.gc()
  // Effect is a root — m is reachable through Effect's sources
  assert_false(m.is_disposed())
}

///|
test "gc: skips sources (signals never collected)" {
  let rt = Runtime::new()
  let sig1 = Signal::new(rt, 1)
  let sig2 = Signal::new(rt, 2)
  rt.gc()
  assert_false(sig1.is_disposed())
  assert_false(sig2.is_disposed())
}

///|
test "gc: idempotent (running twice is safe)" {
  let rt = Runtime::new()
  let sig = Signal::new(rt, 1)
  let m = Memo::new(rt, fn() { sig.get() })
  ignore(m.get())
  rt.gc()
  assert_true(m.is_disposed())
  rt.gc() // second gc is a no-op
  assert_true(m.is_disposed())
}

///|
test "gc: after manual dispose is safe" {
  let rt = Runtime::new()
  let sig = Signal::new(rt, 1)
  let m = Memo::new(rt, fn() { sig.get() })
  ignore(m.get())
  m.dispose()
  rt.gc() // already disposed, gc skips it
  assert_true(m.is_disposed())
}

///|
test "gc: diamond keeps shared deps alive" {
  let rt = Runtime::new()
  let sig = Signal::new(rt, 1)
  let shared = Memo::new(rt, fn() { sig.get() })
  let left = Memo::new(rt, fn() { shared.get() + 1 })
  let right = Memo::new(rt, fn() { shared.get() + 2 })
  let obs_left = left.observe()
  ignore(obs_left.get())
  ignore(right.get()) // compute but not observed
  rt.gc()
  assert_false(shared.is_disposed()) // reachable from left
  assert_false(left.is_disposed())
  assert_true(right.is_disposed()) // unreachable
  obs_left.dispose()
}

///|
test "panic gc: during batch aborts" {
  let rt = Runtime::new()
  let sig = Signal::new(rt, 1)
  rt.batch(fn() {
    sig.set(2)
    rt.gc()
  })
}

///|
test "panic gc: during active computation aborts" {
  let rt = Runtime::new()
  let sig = Signal::new(rt, 1)
  let _m = Memo::new(rt, fn() {
    rt.gc()
    sig.get()
  })
  ignore(_m.get())
}

///|
test "panic gc: during push propagation aborts" {
  let rt = Runtime::new()
  let sig = Signal::new(rt, 1)
  let _eff = Effect::new(rt, fn() {
    ignore(sig.get())
    rt.gc()
  })
  sig.set(2) // triggers push propagation → effect runs → gc aborts
}

///|
test "gc: collects suspended reactive" {
  let rt = Runtime::new()
  let sig = Signal::new(rt, 1)
  let r = Reactive::new(rt, fn() { sig.get() * 2 })
  // Observe then unobserve — reactive is suspended
  let obs = r.observe()
  ignore(obs.get())
  obs.dispose()
  // gc should collect it (Interior, unreachable)
  rt.gc()
  assert_true(r.is_disposed())
}

///|
// gc() traces through gc_dependencies(), which is the current dependencies
// array. An uncomputed memo has empty dependencies, so gc() cannot trace
// through it. This is documented behavior: compute closures must not capture
// handles to cells outside their reachability subgraph. Users should compute
// observed memos (call obs.get()) before calling gc().
test "gc: uncomputed observed memo has empty deps — upstream is swept" {
  let rt = Runtime::new()
  let sig = Signal::new(rt, 1)
  let m1 = Memo::new(rt, fn() { sig.get() + 1 })
  let m2 = Memo::new(rt, fn() { m1.get() * 2 })
  // Observe m2 without computing it first
  let obs = m2.observe()
  rt.gc()
  // m2 is kept alive (observed), but m1 is unreachable (m2.dependencies is empty)
  assert_false(m2.is_disposed())
  assert_true(m1.is_disposed()) // swept because not reachable
  obs.dispose()
}
