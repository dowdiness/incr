///|
test "watch: watch through public API" {
  let rt = @incr.Runtime()
  let sig = @incr.Input(rt, 10)
  let m = @incr.Derived(rt, fn() { sig.get() * 2 })
  let watch = m.watch()
  inspect(watch.read_or_abort(), content="20")
  watch.dispose()
}

///|
test "watch: input.set updates watch.read_or_abort" {
  let rt = @incr.Runtime()
  let sig = @incr.Input(rt, 5)
  let m = @incr.Derived(rt, fn() { sig.get() + 1 })
  let watch = m.watch()
  inspect(watch.read_or_abort(), content="6")
  sig.set(10)
  inspect(watch.read_or_abort(), content="11")
  watch.dispose()
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
  let r = @incr.EagerDerived::EagerDerived(rt, fn() { sig.get() * 5 })
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
