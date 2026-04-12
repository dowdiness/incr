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
test "observer: on_observe fires only on 0-to-1 transition" {
  let rt = Runtime::new()
  let sig = Signal::new(rt, 10)
  let r = Reactive::new(rt, fn() { sig.get() * 2 })
  // First observer: 0→1 transition
  let obs1 = r.observe()
  inspect(obs1.get(), content="20")
  // Second observer: 1→2 transition — on_observe should NOT fire again
  let obs2 = r.observe()
  inspect(obs2.get(), content="20")
  obs1.dispose()
  inspect(obs2.get(), content="20")
  obs2.dispose()
}

///|
test "observer: reactive suspends on last observer removal when no subscribers" {
  let rt = Runtime::new()
  let sig = Signal::new(rt, 10)
  let r = Reactive::new(rt, fn() { sig.get() * 2 })
  let obs = r.observe()
  inspect(obs.get(), content="20")
  // Signal has reactive in subscriber set
  inspect(rt.dependents(sig.id()).length(), content="1")
  obs.dispose()
  // After last observer removed and no subscribers: reactive suspended
  // Signal's subscriber set should be empty (reactive unsubscribed)
  inspect(rt.dependents(sig.id()).length(), content="0")
}

///|
test "observer: reactive does NOT suspend when it has subscribers" {
  let rt = Runtime::new()
  let sig = Signal::new(rt, 10)
  let r = Reactive::new(rt, fn() { sig.get() * 2 })
  // Memo reads the reactive — creates a subscriber link
  let m = Memo::new(rt, fn() { r.get() + 1 })
  let obs_m = m.observe()
  ignore(obs_m.get())
  // Observe and unobserve the reactive itself
  let obs_r = r.observe()
  ignore(obs_r.get())
  obs_r.dispose()
  // Reactive still has m in its subscriber set — must NOT suspend
  inspect(rt.dependents(sig.id()).length(), content="1")
  // Push propagation still works through to the memo
  sig.set(20)
  inspect(obs_m.get(), content="41")
  obs_m.dispose()
}

///|
test "panic observer: observe disposed memo aborts" {
  let rt = Runtime::new()
  let sig = Signal::new(rt, 1)
  let m = Memo::new(rt, fn() { sig.get() })
  m.dispose()
  ignore(m.observe())
}
