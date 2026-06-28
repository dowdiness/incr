///|
test "subscriber: dependents accessible via public API" {
  let rt = Runtime::Runtime()
  let x = Input::Input(rt, 10)
  let doubled = Derived::Derived(rt, () => x.get() * 2)
  let _ = read_derived_for_test(doubled)
  let deps = rt.dependents(x.id())
  inspect(deps.length(), content="1")
  inspect(deps.contains(doubled.id()), content="true")
}

///|
test "subscriber: chain dependencies tracked" {
  let rt = Runtime::Runtime()
  let a = Input::Input(rt, 1)
  let b = Derived::Derived(rt, () => a.get() + 1)
  let c = Derived::Derived(rt, () => b.get_or_abort() * 2)
  let _ = read_derived_for_test(c)
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
test "subscriber: dynamic deps update dependents via public API" {
  let rt = Runtime::Runtime()
  let flag = Input::Input(rt, true)
  let a = Input::Input(rt, 10)
  let b = Input::Input(rt, 20)
  let pick = Derived::Derived(rt, () => {
    if flag.get() {
      a.get()
    } else {
      b.get()
    }
  })
  let _ = read_derived_for_test(pick) // deps: flag, a
  inspect(rt.dependents(a.id()).contains(pick.id()), content="true")
  inspect(rt.dependents(b.id()).contains(pick.id()), content="false")
  // Switch branch: deps become flag, b
  flag.set(false)
  let _ = read_derived_for_test(pick)
  inspect(rt.dependents(a.id()).contains(pick.id()), content="false")
  inspect(rt.dependents(b.id()).contains(pick.id()), content="true")
  // flag always has pick as a dependent
  inspect(rt.dependents(flag.id()).contains(pick.id()), content="true")
}

///|
test "subscriber: dependents returns empty for cross-runtime id" {
  let rt1 = Runtime::Runtime()
  let rt2 = Runtime::Runtime()
  let x = Input::Input(rt1, 10)
  let deps = rt2.dependents(x.id())
  inspect(deps.length(), content="0")
}

///|
test "subscriber: dependents returns empty for disposed id" {
  let rt = Runtime::Runtime()
  let x = Input::Input(rt, 10)
  let doubled = Derived::Derived(rt, () => x.get() * 2)
  let _ = read_derived_for_test(doubled)
  let x_id = x.id()
  inspect(rt.dependents(x_id).contains(doubled.id()), content="true")
  x.dispose()
  inspect(rt.dependents(x_id).length(), content="0")
}

///|
test "push suspension: full lifecycle via public API" {
  let rt = Runtime::Runtime()
  let sig = Input::Input(rt, 10)
  let r = @incr.Reactive::new(rt, fn() { sig.get() * 2 })
  // Observe
  let obs = r.observe()
  inspect(obs.get(), content="20")
  // Change while observed
  sig.set(30)
  inspect(obs.get(), content="60")
  // Unobserve — suspends
  obs.dispose()
  // Change while suspended
  sig.set(100)
  // Re-observe — catches up
  let obs2 = r.observe()
  inspect(obs2.get(), content="200")
  // Change while re-observed
  sig.set(1)
  inspect(obs2.get(), content="2")
  obs2.dispose()
}
