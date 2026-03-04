///|
test "committable: batch commit updates signal value" {
  let rt = Runtime::new()
  let sig = Signal::new(rt, 1)
  rt.batch(() => sig.set(2))
  inspect(sig.get(), content="2")
}

///|
test "committable: batch with no-op set does not bump revision" {
  let rt = Runtime::new()
  let sig = Signal::new(rt, 1)
  let before = rt.current_revision
  rt.batch(() => sig.set(1)) // same value
  inspect(rt.current_revision == before, content="true")
}

///|
test "committable: on_change fires via Committable after batch" {
  let rt = Runtime::new()
  let sig = Signal::new(rt, 1)
  let mut fired = false
  sig.on_change(_v => fired = true)
  rt.batch(() => sig.set(2))
  inspect(fired, content="true")
}

///|
// Regression test: on_change handlers are snapshotted before any callback
// executes. A callback that clears another signal's handler must not suppress
// the other signal's notification in the same batch wave.
test "committable: on_change snapshot — clearing sibling handler does not drop notification" {
  let rt = Runtime::new()
  let sig1 = Signal::new(rt, 1)
  let sig2 = Signal::new(rt, 10)
  let mut fired1 = false
  let mut fired2 = false
  // sig1's callback clears sig2's handler before it would run
  sig1.on_change(_v => {
    fired1 = true
    sig2.clear_on_change()
  })
  sig2.on_change(_v => fired2 = true)
  rt.batch(() => {
    sig1.set(2)
    sig2.set(20)
  })
  // Both handlers were registered before the batch — both must fire.
  inspect(fired1, content="true")
  inspect(fired2, content="true")
}
