///|
test "subscriber: after memo.get(), memo is in all deps' subscribers" {
  let rt = Runtime::Runtime()
  let a = Signal::Signal(rt, 1)
  let b = Signal::Signal(rt, 2)
  let sum = Memo::Memo(rt, () => a.get() + b.get())
  let _ = read_memo_for_test(sum)
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
  let flag = Signal::Signal(rt, true)
  let a = Signal::Signal(rt, 10)
  let b = Signal::Signal(rt, 20)
  let pick = Memo::Memo(rt, () => if flag.get() { a.get() } else { b.get() })
  let _ = read_memo_for_test(pick) // deps: flag, a
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
  let _ = read_memo_for_test(pick) // deps: flag, b
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
  let a = Signal::Signal(rt, 1)
  let m = Memo::Memo(rt, () => a.get() + 1)
  let _ = read_memo_for_test(m)
  let _ = read_memo_for_test(m)
  let a_idx = match rt.core.cell_index[a.id().id] {
    PullSignal(i) => i
    _ => abort("expected PullSignal")
  }
  inspect(rt.pull.signals[a_idx].meta.subscribers.length(), content="1")
}
