///|
test "subscriber: new cells have empty subscribers" {
  let rt = Runtime::new()
  let sig = Signal::new(rt, 10)
  let meta = rt.get_cell(sig.id())
  inspect(meta.subscribers.length(), content="0")
}
