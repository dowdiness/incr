///|
test "watch: derived watch and read_or_abort" {
  let rt = Runtime::Runtime()
  let sig = Input::Input(rt, 10)
  let d = Derived::Derived(rt, fn() { sig.get() * 2 })
  let watch = d.watch()
  inspect(watch.read_or_abort(), content="20")
  watch.dispose()
}

///|
test "watch: reachable derived watch and read_or_abort" {
  let rt = Runtime::Runtime()
  let sig = Input::Input(rt, 5)
  let rd = ReachableDerived::ReachableDerived(rt, fn() { sig.get() + 1 })
  let watch = rd.watch()
  inspect(watch.read_or_abort(), content="6")
  watch.dispose()
}

///|
test "watch: reactive watch and read_or_abort" {
  let rt = Runtime::Runtime()
  let sig = Input::Input(rt, 3)
  let r = EagerDerived::EagerDerived(rt, fn() { sig.get() * 3 })
  let watch = r.watch()
  inspect(watch.read_or_abort(), content="9")
  watch.dispose()
}

///|
test "watch: dispose sets is_disposed" {
  let rt = Runtime::Runtime()
  let sig = Input::Input(rt, 1)
  let d = Derived::Derived(rt, fn() { sig.get() })
  let watch = d.watch()
  inspect(watch.is_disposed(), content="false")
  watch.dispose()
  inspect(watch.is_disposed(), content="true")
}

///|
test "watch: dispose is idempotent" {
  let rt = Runtime::Runtime()
  let sig = Input::Input(rt, 1)
  let d = Derived::Derived(rt, fn() { sig.get() })
  let watch = d.watch()
  watch.dispose()
  watch.dispose() // no abort
  inspect(watch.is_disposed(), content="true")
}

///|
test "panic watch: read_or_abort after dispose aborts" {
  let rt = Runtime::Runtime()
  let sig = Input::Input(rt, 1)
  let d = Derived::Derived(rt, fn() { sig.get() })
  let watch = d.watch()
  watch.dispose()
  ignore(watch.read_or_abort())
}

///|
test "watch: multiple watches on same cell are ref-counted" {
  let rt = Runtime::Runtime()
  let sig = Input::Input(rt, 1)
  let d = Derived::Derived(rt, fn() { sig.get() })
  let watch1 = d.watch()
  let watch2 = d.watch()
  inspect(watch1.read_or_abort(), content="1")
  inspect(watch2.read_or_abort(), content="1")
  watch1.dispose()
  // watch2 still works
  inspect(watch2.read_or_abort(), content="1")
  watch2.dispose()
}

///|
test "watch: on_observe fires only on 0-to-1 transition" {
  let rt = Runtime::Runtime()
  let sig = Input::Input(rt, 10)
  let r = EagerDerived::EagerDerived(rt, fn() { sig.get() * 2 })
  // First watch: 0→1 transition
  let watch1 = r.watch()
  inspect(watch1.read_or_abort(), content="20")
  // Second watch: 1→2 transition — on_observe should NOT fire again
  let watch2 = r.watch()
  inspect(watch2.read_or_abort(), content="20")
  watch1.dispose()
  inspect(watch2.read_or_abort(), content="20")
  watch2.dispose()
}

///|
test "watch: reactive suspends on last watch removal when no subscribers" {
  let rt = Runtime::Runtime()
  let sig = Input::Input(rt, 10)
  let r = EagerDerived::EagerDerived(rt, fn() { sig.get() * 2 })
  let watch = r.watch()
  inspect(watch.read_or_abort(), content="20")
  // Input has reactive in subscriber set
  inspect(rt.dependents(sig.id()).length(), content="1")
  watch.dispose()
  // After last watch removed and no subscribers: reactive suspended
  // Input's subscriber set should be empty (reactive unsubscribed)
  inspect(rt.dependents(sig.id()).length(), content="0")
}

///|
test "watch: reactive does NOT suspend when it has subscribers" {
  let rt = Runtime::Runtime()
  let sig = Input::Input(rt, 10)
  let r = EagerDerived::EagerDerived(rt, fn() { sig.get() * 2 })
  // Memo reads the reactive — creates a subscriber link
  let d = Derived::Derived(rt, fn() { r.get() + 1 })
  let watch_d = d.watch()
  ignore(watch_d.read_or_abort())
  // Watch and unwatch the reactive itself
  let watch_r = r.watch()
  ignore(watch_r.read_or_abort())
  watch_r.dispose()
  // EagerDerived still has m in its subscriber set — must NOT suspend
  inspect(rt.dependents(sig.id()).length(), content="1")
  // Push propagation still works through to the memo
  sig.set(20)
  inspect(watch_d.read_or_abort(), content="41")
  watch_d.dispose()
}

///|
test "watch: reactive reactivation catches up on missed changes" {
  let rt = Runtime::Runtime()
  let sig = Input::Input(rt, 10)
  let r = EagerDerived::EagerDerived(rt, fn() { sig.get() * 2 })
  // Watch, verify, unwatch
  let watch1 = r.watch()
  inspect(watch1.read_or_abort(), content="20")
  watch1.dispose()
  // Input changes while reactive is suspended
  sig.set(50)
  // Re-watch — should see updated value
  let watch2 = r.watch()
  inspect(watch2.read_or_abort(), content="100")
  watch2.dispose()
}

///|
test "watch: repeated suspend/activate cycles" {
  let rt = Runtime::Runtime()
  let sig = Input::Input(rt, 1)
  let r = EagerDerived::EagerDerived(rt, fn() { sig.get() * 10 })
  // Cycle 1
  let watch1 = r.watch()
  inspect(watch1.read_or_abort(), content="10")
  watch1.dispose()
  sig.set(2)
  // Cycle 2
  let watch2 = r.watch()
  inspect(watch2.read_or_abort(), content="20")
  watch2.dispose()
  sig.set(3)
  // Cycle 3
  let watch3 = r.watch()
  inspect(watch3.read_or_abort(), content="30")
  watch3.dispose()
}

///|
test "watch: multiple watches prevent suspension until last disposed" {
  let rt = Runtime::Runtime()
  let sig = Input::Input(rt, 5)
  let r = EagerDerived::EagerDerived(rt, fn() { sig.get() + 1 })
  let watch1 = r.watch()
  let watch2 = r.watch()
  inspect(watch1.read_or_abort(), content="6")
  // Dispose first — on_unobserve should NOT fire (count 2→1)
  watch1.dispose()
  // Push still works
  sig.set(10)
  inspect(watch2.read_or_abort(), content="11")
  // Dispose second — on_unobserve fires (count 1→0), suspend
  watch2.dispose()
  inspect(rt.dependents(sig.id()).length(), content="0")
  // Re-watch catches up
  sig.set(20)
  let watch3 = r.watch()
  inspect(watch3.read_or_abort(), content="21")
  watch3.dispose()
}

///|
test "watch: dispose suspended reactive is idempotent" {
  let rt = Runtime::Runtime()
  let sig = Input::Input(rt, 1)
  let r = EagerDerived::EagerDerived(rt, fn() { sig.get() })
  let watch = r.watch()
  ignore(watch.read_or_abort())
  watch.dispose()
  // EagerDerived is suspended — subscriber links already removed
  // Manual dispose should not double-decrement or abort
  r.dispose()
  assert_true(r.is_disposed())
  assert_false(sig.is_disposed())
}

///|
test "watch: source disposed during suspension — reactivation uses fresh sources" {
  let rt = Runtime::Runtime()
  let sig1 = Input::Input(rt, 10)
  let sig2 = Input::Input(rt, 20)
  let use_sig1 : Ref[Bool] = { val: true }
  let r = EagerDerived::EagerDerived(rt, fn() {
    if use_sig1.val {
      sig1.get()
    } else {
      sig2.get()
    }
  })
  let watch = r.watch()
  inspect(watch.read_or_abort(), content="10")
  watch.dispose()
  // Switch source and change values while suspended
  use_sig1.val = false
  sig1.set(99)
  sig2.set(42)
  // Re-watch — recompute picks up sig2 as new source
  let watch2 = r.watch()
  inspect(watch2.read_or_abort(), content="42")
  watch2.dispose()
}

///|
test "watch: reachable derived reading reactive prevents suspension" {
  let rt = Runtime::Runtime()
  let sig = Input::Input(rt, 5)
  let r = EagerDerived::EagerDerived(rt, fn() { sig.get() * 3 })
  let rd = ReachableDerived::ReachableDerived(rt, fn() { r.get() + 1 })
  let watch_rd = rd.watch()
  ignore(watch_rd.read_or_abort())
  // Watch and unwatch the reactive
  let watch_r = r.watch()
  ignore(watch_r.read_or_abort())
  watch_r.dispose()
  // EagerDerived has rd in its subscriber set — must NOT suspend
  sig.set(10)
  inspect(watch_rd.read_or_abort(), content="31")
  watch_rd.dispose()
}

///|
test "panic watch: on_observe during fixpoint aborts" {
  let rt = Runtime::Runtime()
  let sig = Input::Input(rt, 1)
  let r = EagerDerived::EagerDerived(rt, fn() { sig.get() })
  let input : Relation[Int] = Relation::Relation(rt)
  let output : Relation[Int] = Relation::Relation(rt)
  input.insert(1) |> ignore
  rt.new_rule([input.id()], [output.id()], fn() {
    // Attempt to watch a reactive during fixpoint
    ignore(r.watch())
  })
  |> ignore
  rt.fixpoint()
}

///|
test "panic watch: watch disposed memo aborts" {
  let rt = Runtime::Runtime()
  let sig = Input::Input(rt, 1)
  let d = Derived::Derived(rt, fn() { sig.get() })
  d.dispose()
  ignore(d.watch())
}
