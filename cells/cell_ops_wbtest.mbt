///|
test "cell_ops: signal has ops at its id index" {
  let rt = Runtime::new()
  let sig = Signal::new(rt, 42)
  // Once cell_ops is populated, rt.cell_ops[sig.id().id].cell_id() == sig.id()
  inspect(rt.cell_ops.length(), content="1")
}

///|
test "cell_ops: memo has ops at its id index" {
  let rt = Runtime::new()
  let m = Memo::new(rt, () => 0)
  inspect(rt.cell_ops.length(), content="1")
}
