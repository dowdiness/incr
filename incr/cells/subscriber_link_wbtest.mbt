///|
test "subscriber: after memo.get(), memo is in all deps' subscribers" {
  let rt = Runtime::Runtime()
  let a = Input::Input(rt, 1)
  let b = Input::Input(rt, 2)
  let sum = Derived(rt, () => a.get() + b.get())
  let _ = sum.read_or_abort()
  let a_idx = match rt.core.cell_index[a.id().id] {
    PullSignal(i) => i
    _ => abort("expected PullSignal")
  }
  let b_idx = match rt.core.cell_index[b.id().id] {
    PullSignal(i) => i
    _ => abort("expected PullSignal")
  }
  inspect(
    rt.pull.signals[a_idx].meta.subscribers.contains(sum.id()),
    content="true",
  )
  inspect(
    rt.pull.signals[b_idx].meta.subscribers.contains(sum.id()),
    content="true",
  )
}

///|
test "subscriber: dynamic dep changes update subscriber links" {
  let rt = Runtime::Runtime()
  let flag = Input::Input(rt, true)
  let a = Input::Input(rt, 10)
  let b = Input::Input(rt, 20)
  let pick = Derived(rt, () => if flag.get() { a.get() } else { b.get() })
  let _ = pick.read_or_abort() // deps: flag, a
  let a_idx = match rt.core.cell_index[a.id().id] {
    PullSignal(i) => i
    _ => abort("expected PullSignal")
  }
  let b_idx = match rt.core.cell_index[b.id().id] {
    PullSignal(i) => i
    _ => abort("expected PullSignal")
  }
  inspect(
    rt.pull.signals[a_idx].meta.subscribers.contains(pick.id()),
    content="true",
  )
  inspect(
    rt.pull.signals[b_idx].meta.subscribers.contains(pick.id()),
    content="false",
  )
  flag.set(false)
  let _ = pick.read_or_abort() // deps: flag, b
  inspect(
    rt.pull.signals[a_idx].meta.subscribers.contains(pick.id()),
    content="false",
  )
  inspect(
    rt.pull.signals[b_idx].meta.subscribers.contains(pick.id()),
    content="true",
  )
}

///|
test "subscriber: memo.get() idempotent — no duplicate subscriber entries" {
  let rt = Runtime::Runtime()
  let a = Input::Input(rt, 1)
  let m = Derived(rt, () => a.get() + 1)
  let _ = m.read_or_abort()
  let _ = m.read_or_abort()
  let a_idx = match rt.core.cell_index[a.id().id] {
    PullSignal(i) => i
    _ => abort("expected PullSignal")
  }
  inspect(rt.pull.signals[a_idx].meta.subscribers.length(), content="1")
}
