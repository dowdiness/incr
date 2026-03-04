///|
test "committable: batch commit updates signal value" {
  let rt = Runtime::new()
  let sig = Signal::new(rt, 1)
  rt.batch(() => { sig.set(2) })
  inspect(sig.get(), content="2")
}

///|
test "committable: batch with no-op set does not bump revision" {
  let rt = Runtime::new()
  let sig = Signal::new(rt, 1)
  let before = rt.current_revision
  rt.batch(() => { sig.set(1) }) // same value
  inspect(rt.current_revision == before, content="true")
}

///|
test "committable: on_change fires via Committable after batch" {
  let rt = Runtime::new()
  let sig = Signal::new(rt, 1)
  let mut fired = false
  sig.on_change(fn(_v) { fired = true })
  rt.batch(() => { sig.set(2) })
  inspect(fired, content="true")
}
