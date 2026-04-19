///|
test "ensure_computed_untracked: first-read on never-computed memo triggers compute" {
  let rt = Runtime::new()
  let signal = Signal::new(rt, 7)
  let mut compute_count = 0
  let memo = Memo::new(rt, () => {
    compute_count = compute_count + 1
    signal.get() * 2
  })
  let data = rt.get_memo_data(memo.id())
  // Fresh memo has never been computed.
  inspect(data.verified_at == Revision::initial(), content="true")
  // Note: `compute_count` will only hold 1 after ensure fires the first
  // compute — on a fresh runtime verify has nothing to do, so the plan's
  // `data.compute()` branch is the interesting one.
  let _ = rt.ensure_computed_untracked(memo.id())
  inspect(compute_count, content="1")
  // Second call should not re-run the closure (pull_verify branch sees fresh).
  let _ = rt.ensure_computed_untracked(memo.id())
  inspect(compute_count, content="1")
}

///|
test "ensure_computed_untracked: does not record ordinary dep on caller frame" {
  let rt = Runtime::new()
  let signal = Signal::new(rt, 1)
  let inner = Memo::new(rt, () => signal.get() * 10)
  // Pre-compute inner outside tracking.
  let _ = rt.ensure_computed_untracked(inner.id())

  // Outer memo calls ensure_computed_untracked on inner but must NOT
  // record inner as an ordinary dep.
  let outer = Memo::new(rt, () => {
    let _ = rt.ensure_computed_untracked(inner.id())
    42
  })
  let _ = outer.observe().get()
  let outer_data = rt.get_memo_data(outer.id())
  inspect(outer_data.dependencies.contains(inner.id()), content="false")
}
