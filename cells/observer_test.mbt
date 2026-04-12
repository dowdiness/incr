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
test "observer: reactive reactivation catches up on missed changes" {
  let rt = Runtime::new()
  let sig = Signal::new(rt, 10)
  let r = Reactive::new(rt, fn() { sig.get() * 2 })
  // Observe, verify, unobserve
  let obs1 = r.observe()
  inspect(obs1.get(), content="20")
  obs1.dispose()
  // Signal changes while reactive is suspended
  sig.set(50)
  // Re-observe — should see updated value
  let obs2 = r.observe()
  inspect(obs2.get(), content="100")
  obs2.dispose()
}

///|
test "observer: repeated suspend/activate cycles" {
  let rt = Runtime::new()
  let sig = Signal::new(rt, 1)
  let r = Reactive::new(rt, fn() { sig.get() * 10 })
  // Cycle 1
  let obs1 = r.observe()
  inspect(obs1.get(), content="10")
  obs1.dispose()
  sig.set(2)
  // Cycle 2
  let obs2 = r.observe()
  inspect(obs2.get(), content="20")
  obs2.dispose()
  sig.set(3)
  // Cycle 3
  let obs3 = r.observe()
  inspect(obs3.get(), content="30")
  obs3.dispose()
}

///|
test "observer: multiple observers prevent suspension until last disposed" {
  let rt = Runtime::new()
  let sig = Signal::new(rt, 5)
  let r = Reactive::new(rt, fn() { sig.get() + 1 })
  let obs1 = r.observe()
  let obs2 = r.observe()
  inspect(obs1.get(), content="6")
  // Dispose first — on_unobserve should NOT fire (count 2→1)
  obs1.dispose()
  // Push still works
  sig.set(10)
  inspect(obs2.get(), content="11")
  // Dispose second — on_unobserve fires (count 1→0), suspend
  obs2.dispose()
  inspect(rt.dependents(sig.id()).length(), content="0")
  // Re-observe catches up
  sig.set(20)
  let obs3 = r.observe()
  inspect(obs3.get(), content="21")
  obs3.dispose()
}

///|
test "observer: dispose suspended reactive is idempotent" {
  let rt = Runtime::new()
  let sig = Signal::new(rt, 1)
  let r = Reactive::new(rt, fn() { sig.get() })
  let obs = r.observe()
  ignore(obs.get())
  obs.dispose()
  // Reactive is suspended — subscriber links already removed
  // Manual dispose should not double-decrement or abort
  r.dispose()
  assert_true(r.is_disposed())
  assert_false(sig.is_disposed())
}

///|
test "observer: source disposed during suspension — reactivation uses fresh sources" {
  let rt = Runtime::new()
  let sig1 = Signal::new(rt, 10)
  let sig2 = Signal::new(rt, 20)
  let use_sig1 : Ref[Bool] = { val: true }
  let r = Reactive::new(rt, fn() {
    if use_sig1.val {
      sig1.get()
    } else {
      sig2.get()
    }
  })
  let obs = r.observe()
  inspect(obs.get(), content="10")
  obs.dispose()
  // Switch source and change values while suspended
  use_sig1.val = false
  sig1.set(99)
  sig2.set(42)
  // Re-observe — recompute picks up sig2 as new source
  let obs2 = r.observe()
  inspect(obs2.get(), content="42")
  obs2.dispose()
}

///|
test "observer: hybrid memo reading reactive prevents suspension" {
  let rt = Runtime::new()
  let sig = Signal::new(rt, 5)
  let r = Reactive::new(rt, fn() { sig.get() * 3 })
  let h = HybridMemo::new(rt, fn() { r.get() + 1 })
  let obs_h = h.observe()
  ignore(obs_h.get())
  // Observe and unobserve the reactive
  let obs_r = r.observe()
  ignore(obs_r.get())
  obs_r.dispose()
  // Reactive has h in its subscriber set — must NOT suspend
  sig.set(10)
  inspect(obs_h.get(), content="31")
  obs_h.dispose()
}

///|
test "panic observer: on_observe during fixpoint aborts" {
  let rt = Runtime::new()
  let sig = Signal::new(rt, 1)
  let r = Reactive::new(rt, fn() { sig.get() })
  let input : Relation[Int] = Relation::new(rt)
  let output : Relation[Int] = Relation::new(rt)
  input.insert(1) |> ignore
  rt.new_rule([input.id()], [output.id()], fn() {
    // Attempt to observe a reactive during fixpoint
    ignore(r.observe())
  })
  |> ignore
  rt.fixpoint()
}

///|
test "panic observer: observe disposed memo aborts" {
  let rt = Runtime::new()
  let sig = Signal::new(rt, 1)
  let m = Memo::new(rt, fn() { sig.get() })
  m.dispose()
  ignore(m.observe())
}
