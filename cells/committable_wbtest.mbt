///|
test "committable: batch_pending holds entry after set" {
  let rt = Runtime::new()
  let sig = Signal::new(rt, 1)
  rt.batch_depth = 1  // simulate batch
  sig.set(2)
  rt.batch_depth = 0
  // With Committable, batch_pending should have 1 entry
  inspect(rt.batch_pending.length(), content="1")
}
