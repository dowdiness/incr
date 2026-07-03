///|
test "subscriber: new cells have empty subscribers" {
  let rt = Runtime::Runtime()
  let sig = Input::Input(rt, 10)
  let sig_data = rt.get_pull_input(sig.id())
  inspect(sig_data.meta.subscribers.length(), content="0")
}

///|
test "subscriber: memo subscribes to its dependencies" {
  let rt = Runtime::Runtime()
  let a = Input::Input(rt, 1)
  let b = Input::Input(rt, 2)
  let sum = Derived(rt, () => a.get() + b.get())
  let _ = sum.read_or_abort()
  // a and b should list sum as a subscriber
  let a_data = rt.get_pull_input(a.id())
  let b_data = rt.get_pull_input(b.id())
  inspect(a_data.meta.subscribers.contains(sum.id()), content="true")
  inspect(b_data.meta.subscribers.contains(sum.id()), content="true")
}

///|
test "subscriber: dynamic dep change updates subscribers" {
  let rt = Runtime::Runtime()
  let flag = Input::Input(rt, true)
  let a = Input::Input(rt, 10)
  let b = Input::Input(rt, 20)
  let pick = Derived(rt, () => if flag.get() { a.get() } else { b.get() })
  let _ = pick.read_or_abort()
  let a_data = rt.get_pull_input(a.id())
  let b_data = rt.get_pull_input(b.id())
  inspect(a_data.meta.subscribers.contains(pick.id()), content="true")
  inspect(b_data.meta.subscribers.contains(pick.id()), content="false")
  // Switch branch: deps become flag, b
  // PullInputData has reference semantics — no need to re-fetch
  flag.set(false)
  let _ = pick.read_or_abort()
  inspect(a_data.meta.subscribers.contains(pick.id()), content="false")
  inspect(b_data.meta.subscribers.contains(pick.id()), content="true")
}

///|
test "subscriber: dependents returns subscriber list" {
  let rt = Runtime::Runtime()
  let a = Input::Input(rt, 1)
  let m1 = Derived(rt, () => a.get() + 1)
  let m2 = Derived(rt, () => a.get() * 2)
  let _ = m1.read_or_abort()
  let _ = m2.read_or_abort()
  let deps = rt.dependents(a.id())
  inspect(deps.length(), content="2")
  inspect(deps.contains(m1.id()), content="true")
  inspect(deps.contains(m2.id()), content="true")
}

///|
test "subscriber: dependents returns empty for leaf memo" {
  let rt = Runtime::Runtime()
  let a = Input::Input(rt, 1)
  let m = Derived(rt, () => a.get())
  let _ = m.read_or_abort()
  let deps = rt.dependents(m.id())
  inspect(deps.length(), content="0")
}

///|
test "subscriber: dependents ignores stale reactive id after slot reuse" {
  let rt = Runtime::Runtime()
  let s = Input::Input(rt, 1)
  let old = EagerDerived::EagerDerived(rt, () => s.get())
  let old_id = old.id()
  let old_idx = match rt.core.cell_index[old_id.id] {
    PushReactive(i) => i
    _ => abort("expected PushReactive")
  }
  old.dispose()
  inspect(rt.dependents(old_id).length(), content="0")
  let reused = EagerDerived::EagerDerived(rt, () => s.get() + 1)
  let reused_idx = match rt.core.cell_index[reused.id().id] {
    PushReactive(i) => i
    _ => abort("expected PushReactive")
  }
  inspect(reused_idx, content=old_idx.to_string())
  let downstream = EagerDerived::EagerDerived(rt, () => reused.get() * 2)
  inspect(rt.dependents(reused.id()).contains(downstream.id()), content="true")
  // Keep stale dispatch metadata non-empty to pin the disposed guard ordering.
  rt.core.cell_ops[old_id.id].subscribers().add(downstream.id())
  inspect(rt.dependents(old_id).length(), content="0")
}

///|
test "subscriber: memo.get() is idempotent for subscribers" {
  let rt = Runtime::Runtime()
  let a = Input::Input(rt, 1)
  let m = Derived(rt, () => a.get() + 1)
  let _ = m.read_or_abort()
  let _ = m.read_or_abort()
  let sig_data = rt.get_pull_input(a.id())
  inspect(sig_data.meta.subscribers.contains(m.id()), content="true")
  inspect(sig_data.meta.subscribers.length(), content="1")
}

///|
test "subscriber: cell_info includes subscribers" {
  let rt = Runtime::Runtime()
  let a = Input::Input(rt, 1)
  let m = Derived(rt, () => a.get() + 1)
  let _ = m.read_or_abort()
  match rt.cell_info(a.id()) {
    Some(info) => inspect(info.subscribers.contains(m.id()), content="true")
    None => abort("expected cell info")
  }
}
