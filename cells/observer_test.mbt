///|
test "observer: memo observe and get" {
  let rt = Runtime::new()
  let sig = Signal::new(rt, 10)
  let m = Memo::new(rt, fn() { sig.get() * 2 })
  let obs = m.observe()
  inspect(obs.get(), content="20")
  obs.dispose()
}

///|
test "observer: hybrid_memo observe and get" {
  let rt = Runtime::new()
  let sig = Signal::new(rt, 5)
  let h = HybridMemo::new(rt, fn() { sig.get() + 1 })
  let obs = h.observe()
  inspect(obs.get(), content="6")
  obs.dispose()
}

///|
test "observer: reactive observe and get" {
  let rt = Runtime::new()
  let sig = Signal::new(rt, 3)
  let r = Reactive::new(rt, fn() { sig.get() * 3 })
  let obs = r.observe()
  inspect(obs.get(), content="9")
  obs.dispose()
}

///|
test "observer: dispose sets is_disposed" {
  let rt = Runtime::new()
  let sig = Signal::new(rt, 1)
  let m = Memo::new(rt, fn() { sig.get() })
  let obs = m.observe()
  inspect(obs.is_disposed(), content="false")
  obs.dispose()
  inspect(obs.is_disposed(), content="true")
}

///|
test "observer: dispose is idempotent" {
  let rt = Runtime::new()
  let sig = Signal::new(rt, 1)
  let m = Memo::new(rt, fn() { sig.get() })
  let obs = m.observe()
  obs.dispose()
  obs.dispose() // no abort
  inspect(obs.is_disposed(), content="true")
}

///|
test "panic observer: get after dispose aborts" {
  let rt = Runtime::new()
  let sig = Signal::new(rt, 1)
  let m = Memo::new(rt, fn() { sig.get() })
  let obs = m.observe()
  obs.dispose()
  ignore(obs.get())
}

///|
test "observer: multiple observers on same cell are ref-counted" {
  let rt = Runtime::new()
  let sig = Signal::new(rt, 1)
  let m = Memo::new(rt, fn() { sig.get() })
  let obs1 = m.observe()
  let obs2 = m.observe()
  inspect(obs1.get(), content="1")
  inspect(obs2.get(), content="1")
  obs1.dispose()
  // obs2 still works
  inspect(obs2.get(), content="1")
  obs2.dispose()
}

///|
test "panic observer: observe disposed memo aborts" {
  let rt = Runtime::new()
  let sig = Signal::new(rt, 1)
  let m = Memo::new(rt, fn() { sig.get() })
  m.dispose()
  ignore(m.observe())
}
