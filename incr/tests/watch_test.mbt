///|
test "observer: observe through public API" {
  let rt = @incr.Runtime()
  let sig = @incr.Input(rt, 10)
  let m = @incr.Derived(rt, fn() { sig.get() * 2 })
  let obs = m.observe()
  inspect(obs.get(), content="20")
  obs.dispose()
}

///|
test "observer: input.set updates observer.get" {
  let rt = @incr.Runtime()
  let sig = @incr.Input(rt, 5)
  let m = @incr.Derived(rt, fn() { sig.get() + 1 })
  let obs = m.observe()
  inspect(obs.get(), content="6")
  sig.set(10)
  inspect(obs.get(), content="11")
  obs.dispose()
}

///|
test "runtime: read one-shot convenience" {
  let rt = @incr.Runtime()
  let sig = @incr.Input(rt, 7)
  let m = @incr.Derived(rt, fn() { sig.get() * 3 })
  inspect(read_derived_for_test(m), content="21")
}

///|
test "runtime: read_hybrid one-shot convenience" {
  let rt = @incr.Runtime()
  let sig = @incr.Input(rt, 4)
  let h = @incr.ReachableDerived(rt, fn() { sig.get() + 2 })
  inspect(read_reachable_for_test(h), content="6")
}

///|
test "runtime: read_reactive one-shot convenience" {
  let rt = @incr.Runtime()
  let sig = @incr.Input(rt, 3)
  let r = @incr.Reactive::new(rt, fn() { sig.get() * 5 })
  inspect(read_reactive_for_test(r), content="15")
}

///|
test "panic runtime: read on disposed memo aborts" {
  let rt = @incr.Runtime()
  let sig = @incr.Input(rt, 1)
  let m = @incr.Derived(rt, fn() { sig.get() })
  rt.dispose_cell(m.id())
  ignore(read_derived_for_test(m))
}
