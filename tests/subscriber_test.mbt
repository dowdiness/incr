///|
test "subscriber: dependents accessible via public API" {
  let rt = Runtime::new()
  let x = Signal::new(rt, 10)
  let doubled = Memo::new(rt, () => x.get() * 2)
  let _ = doubled.get()
  let deps = rt.dependents(x.id())
  inspect(deps.length(), content="1")
  inspect(deps.contains(doubled.id()), content="true")
}

///|
test "subscriber: chain dependencies tracked" {
  let rt = Runtime::new()
  let a = Signal::new(rt, 1)
  let b = Memo::new(rt, () => a.get() + 1)
  let c = Memo::new(rt, () => b.get() * 2)
  let _ = c.get()
  // a -> b -> c
  let a_deps = rt.dependents(a.id())
  inspect(a_deps.length(), content="1")
  inspect(a_deps.contains(b.id()), content="true")
  let b_deps = rt.dependents(b.id())
  inspect(b_deps.length(), content="1")
  inspect(b_deps.contains(c.id()), content="true")
  let c_deps = rt.dependents(c.id())
  inspect(c_deps.length(), content="0")
}

///|
test "subscriber: dependents returns empty for cross-runtime id" {
  let rt1 = Runtime::new()
  let rt2 = Runtime::new()
  let x = Signal::new(rt1, 10)
  let deps = rt2.dependents(x.id())
  inspect(deps.length(), content="0")
}
