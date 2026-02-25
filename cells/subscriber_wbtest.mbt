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
  // CellMeta has reference semantics — no need to re-fetch
  flag.set(false)
  let _ = pick.get()
  inspect(a_meta.subscribers.contains(pick.id()), content="false")
  inspect(b_meta.subscribers.contains(pick.id()), content="true")
}

///|
test "subscriber: dependents returns subscriber list" {
  let rt = Runtime::new()
  let a = Signal::new(rt, 1)
  let m1 = Memo::new(rt, () => a.get() + 1)
  let m2 = Memo::new(rt, () => a.get() * 2)
  let _ = m1.get()
  let _ = m2.get()
  let deps = rt.dependents(a.id())
  inspect(deps.length(), content="2")
  inspect(deps.contains(m1.id()), content="true")
  inspect(deps.contains(m2.id()), content="true")
}

///|
test "subscriber: dependents returns empty for leaf memo" {
  let rt = Runtime::new()
  let a = Signal::new(rt, 1)
  let m = Memo::new(rt, () => a.get())
  let _ = m.get()
  let deps = rt.dependents(m.id())
  inspect(deps.length(), content="0")
}

///|
test "subscriber: memo.get() is idempotent for subscribers" {
  let rt = Runtime::new()
  let a = Signal::new(rt, 1)
  let m = Memo::new(rt, () => a.get() + 1)
  let _ = m.get()
  let _ = m.get()
  let meta = rt.get_cell(a.id())
  inspect(meta.subscribers.contains(m.id()), content="true")
  inspect(meta.subscribers.length(), content="1")
}

///|
test "subscriber: cell_info includes subscribers" {
  let rt = Runtime::new()
  let a = Signal::new(rt, 1)
  let m = Memo::new(rt, () => a.get() + 1)
  let _ = m.get()
  match rt.cell_info(a.id()) {
    Some(info) => inspect(info.subscribers.contains(m.id()), content="true")
    None => abort("expected cell info")
  }
}
