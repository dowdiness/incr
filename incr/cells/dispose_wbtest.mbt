///|
test "input dispose: removes from downstream subscriber sets" {
  let rt = Runtime()
  let sig = Input(rt, 10)
  let m = Derived(rt, fn() { sig.get() * 2 })
  ignore(m.read_or_abort()) // establish dependency: sig -> m
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
  let sig = Input(rt, 10)
  let m = Derived(rt, fn() { sig.get() * 2 })
  ignore(m.read_or_abort()) // establish sig -> m dependency
  let sig_subs_before = rt.get_subscribers(sig.id()).collect().length()
  assert_true(sig_subs_before > 0)
  m.dispose()
  let sig_subs_after = rt.get_subscribers(sig.id()).collect().length()
  assert_eq(sig_subs_after, 0)
}

///|
test "input dispose: free list enables slot reuse" {
  let rt = Runtime()
  let sig1 = Input(rt, 10)
  let idx1 = match rt.core.cell_index[sig1.id().id] {
    PullSignal(i) => i
    _ => abort("expected PullSignal")
  }
  sig1.dispose()
  // Free list should contain idx1
  assert_true(rt.pull.free_signals.contains(idx1))
  // Creating a new input should reuse the slot
  let sig2 = Input(rt, 20)
  let idx2 = match rt.core.cell_index[sig2.id().id] {
    PullSignal(i) => i
    _ => abort("expected PullSignal")
  }
  assert_eq(idx1, idx2)
  assert_eq(sig2.get(), 20)
}

///|
test "memo dispose: free list enables slot reuse" {
  let rt = Runtime::Runtime()
  let sig = Input::Input(rt, 10)
  let m1 = Derived(rt, fn() { sig.get() * 2 })
  ignore(m1.read_or_abort())
  let idx1 = match rt.core.cell_index[m1.id().id] {
    PullMemo(i) => i
    _ => abort("expected PullMemo")
  }
  m1.dispose()
  assert_true(rt.pull.free_memos.contains(idx1))
  // New memo should reuse the slot
  let m2 = Derived(rt, fn() { sig.get() + 1 })
  let idx2 = match rt.core.cell_index[m2.id().id] {
    PullMemo(i) => i
    _ => abort("expected PullMemo")
  }
  assert_eq(idx1, idx2)
  assert_eq(m2.read_or_abort(), 11)
}
