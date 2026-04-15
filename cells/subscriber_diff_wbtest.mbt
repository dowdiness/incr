///|
test "diff_subscribers: add new deps" {
  let rt = Runtime::new()
  let s1 = Signal::new(rt, 1)
  let s2 = Signal::new(rt, 2)
  let m = Memo::new(rt, fn() { s1.get() })
  let obs = m.observe()
  // m currently depends on s1 only. Simulate a dep change to [s1, s2].
  let old_deps = [s1.id()]
  let new_deps = [s1.id(), s2.id()]
  rt.diff_and_update_subscribers(m.id(), old_deps, new_deps) |> ignore
  // s2 should now have m as a subscriber
  let s2_subs = rt.dependents(s2.id())
  inspect(s2_subs.contains(m.id()), content="true")
  obs.dispose()
}

///|
test "diff_subscribers: remove old deps" {
  let rt = Runtime::new()
  let s1 = Signal::new(rt, 1)
  let s2 = Signal::new(rt, 2)
  let m = Memo::new(rt, fn() { s1.get() + s2.get() })
  let obs = m.observe()
  // m depends on [s1, s2]. Simulate dep change to [s1] only.
  let old_deps = [s1.id(), s2.id()]
  let new_deps = [s1.id()]
  rt.diff_and_update_subscribers(m.id(), old_deps, new_deps) |> ignore
  // s2 should no longer have m as subscriber
  let s2_subs = rt.dependents(s2.id())
  inspect(s2_subs.contains(m.id()), content="false")
  obs.dispose()
}

///|
test "diff_subscribers: no change is no-op" {
  let rt = Runtime::new()
  let s1 = Signal::new(rt, 1)
  let m = Memo::new(rt, fn() { s1.get() })
  let obs = m.observe()
  // Force computation to establish subscriber links
  rt.read(m) |> ignore
  let deps = [s1.id()]
  // Diff identical lists — should be a no-op
  rt.diff_and_update_subscribers(m.id(), deps, deps) |> ignore
  let s1_subs = rt.dependents(s1.id())
  inspect(s1_subs.contains(m.id()), content="true")
  obs.dispose()
}
