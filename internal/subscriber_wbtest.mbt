///|
test "subscriber: new cells have empty subscribers" {
  let rt = Runtime::new()
  let sig = Signal::new(rt, 10)
  let meta = rt.get_cell(sig.id())
  inspect(meta.subscribers.length(), content="0")
}

///|
test "subscriber: memo subscribes to its dependencies" {
  let rt = Runtime::new()
  let a = Signal::new(rt, 1)
  let b = Signal::new(rt, 2)
  let sum = Memo::new(rt, () => a.get() + b.get())
  let _ = sum.get()
  // a and b should list sum as a subscriber
  let a_meta = rt.get_cell(a.id())
  let b_meta = rt.get_cell(b.id())
  inspect(a_meta.subscribers.contains(sum.id()), content="true")
  inspect(b_meta.subscribers.contains(sum.id()), content="true")
}

///|
test "subscriber: dynamic dep change updates subscribers" {
  let rt = Runtime::new()
  let flag = Signal::new(rt, true)
  let a = Signal::new(rt, 10)
  let b = Signal::new(rt, 20)
  let pick = Memo::new(rt, () => if flag.get() { a.get() } else { b.get() })
  let _ = pick.get() // deps: flag, a
  let a_meta = rt.get_cell(a.id())
  let b_meta = rt.get_cell(b.id())
  inspect(a_meta.subscribers.contains(pick.id()), content="true")
  inspect(b_meta.subscribers.contains(pick.id()), content="false")
  // Switch branch: deps become flag, b
  flag.set(false)
  let _ = pick.get()
  let a_meta2 = rt.get_cell(a.id())
  let b_meta2 = rt.get_cell(b.id())
  inspect(a_meta2.subscribers.contains(pick.id()), content="false")
  inspect(b_meta2.subscribers.contains(pick.id()), content="true")
}
