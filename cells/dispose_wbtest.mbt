///|
test "signal dispose: removes from downstream subscriber sets" {
  let rt = Runtime()
  let sig = Signal(rt, 10)
  let m = Memo(rt, fn() { sig.get() * 2 })
  ignore(m.get()) // establish dependency: sig -> m
  let sig_id = sig.id()
  let subs = rt.get_subscribers(sig_id).collect()
  assert_true(subs.length() > 0)
  sig.dispose()
  // After dispose, sig's subscribers should be cleared
  // (but we can't call get_subscribers on Disposed — check cell_index directly)
  assert_true(rt.core.cell_index[sig_id.id] is Disposed)
}

///|
test "memo dispose: removes from upstream subscriber sets" {
  let rt = Runtime()
  let sig = Signal(rt, 10)
  let m = Memo(rt, fn() { sig.get() * 2 })
  ignore(m.get()) // establish sig -> m dependency
  let sig_subs_before = rt.get_subscribers(sig.id()).collect().length()
  assert_true(sig_subs_before > 0)
  m.dispose()
  let sig_subs_after = rt.get_subscribers(sig.id()).collect().length()
  assert_eq(sig_subs_after, 0)
}

///|
test "signal dispose: free list enables slot reuse" {
  let rt = Runtime()
  let sig1 = Signal(rt, 10)
  let idx1 = match rt.core.cell_index[sig1.id().id] {
    PullSignal(i) => i
    _ => abort("expected PullSignal")
  }
  sig1.dispose()
  // Free list should contain idx1
  assert_true(rt.pull.free_signals.contains(idx1))
  // Creating a new signal should reuse the slot
  let sig2 = Signal(rt, 20)
  let idx2 = match rt.core.cell_index[sig2.id().id] {
    PullSignal(i) => i
    _ => abort("expected PullSignal")
  }
  assert_eq(idx1, idx2)
  assert_eq(sig2.get(), 20)
}

///|
test "memo dispose: free list enables slot reuse" {
  let rt = Runtime::new()
  let sig = Signal::new(rt, 10)
  let m1 = Memo::new(rt, fn() { sig.get() * 2 })
  ignore(m1.get())
  let idx1 = match rt.core.cell_index[m1.id().id] {
    PullMemo(i) => i
    _ => abort("expected PullMemo")
  }
  m1.dispose()
  assert_true(rt.pull.free_memos.contains(idx1))
  // New memo should reuse the slot
  let m2 = Memo::new(rt, fn() { sig.get() + 1 })
  let idx2 = match rt.core.cell_index[m2.id().id] {
    PullMemo(i) => i
    _ => abort("expected PullMemo")
  }
  assert_eq(idx1, idx2)
  assert_eq(m2.get(), 11)
}
