///|
test "subscriber: new cells have empty subscribers" {
  let rt = Runtime::new()
  let sig = Signal::new(rt, 10)
  let sig_data = rt.get_pull_signal(sig.id())
  inspect(sig_data.meta.subscribers.length(), content="0")
}

///|
test "subscriber: memo subscribes to its dependencies" {
  let rt = Runtime::new()
  let a = Signal::new(rt, 1)
  let b = Signal::new(rt, 2)
  let sum = Memo::new(rt, () => a.get() + b.get())
  let _ = rt.read(sum)
  // a and b should list sum as a subscriber
  let a_data = rt.get_pull_signal(a.id())
  let b_data = rt.get_pull_signal(b.id())
  inspect(a_data.meta.subscribers.contains(sum.id()), content="true")
  inspect(b_data.meta.subscribers.contains(sum.id()), content="true")
}

///|
test "subscriber: dynamic dep change updates subscribers" {
  let rt = Runtime::new()
  let flag = Signal::new(rt, true)
  let a = Signal::new(rt, 10)
  let b = Signal::new(rt, 20)
  let pick = Memo::new(rt, () => if flag.get() { a.get() } else { b.get() })
  let _ = rt.read(pick) // deps: flag, a
  let a_data = rt.get_pull_signal(a.id())
  let b_data = rt.get_pull_signal(b.id())
  inspect(a_data.meta.subscribers.contains(pick.id()), content="true")
  inspect(b_data.meta.subscribers.contains(pick.id()), content="false")
  // Switch branch: deps become flag, b
  // PullSignalData has reference semantics — no need to re-fetch
  flag.set(false)
  let _ = rt.read(pick)
  inspect(a_data.meta.subscribers.contains(pick.id()), content="false")
  inspect(b_data.meta.subscribers.contains(pick.id()), content="true")
}

///|
test "subscriber: dependents returns subscriber list" {
  let rt = Runtime::new()
  let a = Signal::new(rt, 1)
  let m1 = Memo::new(rt, () => a.get() + 1)
  let m2 = Memo::new(rt, () => a.get() * 2)
  let _ = rt.read(m1)
  let _ = rt.read(m2)
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
  let _ = rt.read(m)
  let deps = rt.dependents(m.id())
  inspect(deps.length(), content="0")
}

///|
test "subscriber: memo.get() is idempotent for subscribers" {
  let rt = Runtime::new()
  let a = Signal::new(rt, 1)
  let m = Memo::new(rt, () => a.get() + 1)
  let _ = rt.read(m)
  let _ = rt.read(m)
  let sig_data = rt.get_pull_signal(a.id())
  inspect(sig_data.meta.subscribers.contains(m.id()), content="true")
  inspect(sig_data.meta.subscribers.length(), content="1")
}

///|
test "subscriber: cell_info includes subscribers" {
  let rt = Runtime::new()
  let a = Signal::new(rt, 1)
  let m = Memo::new(rt, () => a.get() + 1)
  let _ = rt.read(m)
  match rt.cell_info(a.id()) {
    Some(info) => inspect(info.subscribers.contains(m.id()), content="true")
    None => abort("expected cell info")
  }
}
