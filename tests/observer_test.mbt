///|
test "observer: observe through public API" {
  let rt = @incr.Runtime()
  let sig = @incr.Signal(rt, 10)
  let m = @incr.Memo(rt, fn() { sig.get() * 2 })
  let obs = m.observe()
  inspect(obs.get(), content="20")
  obs.dispose()
}

///|
test "observer: signal.set updates observer.get" {
  let rt = @incr.Runtime()
  let sig = @incr.Signal(rt, 5)
  let m = @incr.Memo(rt, fn() { sig.get() + 1 })
  let obs = m.observe()
  inspect(obs.get(), content="6")
  sig.set(10)
  inspect(obs.get(), content="11")
  obs.dispose()
}

///|
test "runtime: read one-shot convenience" {
  let rt = @incr.Runtime()
  let sig = @incr.Signal(rt, 7)
  let m = @incr.Memo(rt, fn() { sig.get() * 3 })
  inspect(rt.read(m), content="21")
}

///|
test "runtime: read_hybrid one-shot convenience" {
  let rt = @incr.Runtime()
  let sig = @incr.Signal(rt, 4)
  let h = @incr.HybridMemo(rt, fn() { sig.get() + 2 })
  inspect(rt.read_hybrid(h), content="6")
}

///|
test "runtime: read_reactive one-shot convenience" {
  let rt = @incr.Runtime()
  let sig = @incr.Signal(rt, 3)
  let r = @incr.Reactive::new(rt, fn() { sig.get() * 5 })
  inspect(rt.read_reactive(r), content="15")
}

///|
test "panic runtime: read on disposed memo aborts" {
  let rt = @incr.Runtime()
  let sig = @incr.Signal(rt, 1)
  let m = @incr.Memo(rt, fn() { sig.get() })
  m.dispose()
  ignore(rt.read(m))
}
