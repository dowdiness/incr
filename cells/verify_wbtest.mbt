///|
// Characterization test: this simulates the state left behind if memo
// recomputation aborts after setting in_progress and pushing tracking.
test "verify leak simulation: stale in_progress causes spurious cycle" {
  let rt = Runtime::new()
  let sig = Signal::new(rt, 0)
  let memo = Memo::new(rt, () => sig.get() + 1)
  let meta = rt.get_memo_data(memo.id())
  meta.in_progress = true
  rt.push_tracking(memo.id())

  match memo.get_result() {
    Ok(_) => abort("expected cycle error")
    Err(e) => {
      inspect(e.cell() == memo.id(), content="true")
      // Path contains leaked tracking frame + closing id.
      inspect(e.path().length(), content="2")
    }
  }
  inspect(meta.in_progress, content="true")
  inspect(rt.core.tracking_stack.length(), content="1")
}

///|
// Characterization test: if leaked state is cleaned manually, normal reads
// succeed again.
test "verify leak simulation: manual cleanup recovers memo reads" {
  let rt = Runtime::new()
  let sig = Signal::new(rt, 0)
  let memo = Memo::new(rt, () => sig.get() + 1)
  let meta = rt.get_memo_data(memo.id())
  meta.in_progress = true
  rt.push_tracking(memo.id())

  meta.in_progress = false
  ignore(rt.pop_tracking())

  inspect(rt.read(memo), content="1")
}

///|
test "memo_get_or_returns_fallback_on_cycle_error" {
  let rt = Runtime::new()
  let sig = Signal::new(rt, 0)
  let memo = Memo::new(rt, () => sig.get() + 1)
  let meta = rt.get_memo_data(memo.id())
  meta.in_progress = true
  rt.push_tracking(memo.id())

  inspect(memo.get_or(-123), content="-123")

  meta.in_progress = false
  ignore(rt.pop_tracking())
}

///|
test "memo_get_or_else_receives_cycle_error" {
  let rt = Runtime::new()
  let sig = Signal::new(rt, 0)
  let memo = Memo::new(rt, () => sig.get() + 1)
  let meta = rt.get_memo_data(memo.id())
  meta.in_progress = true
  rt.push_tracking(memo.id())

  let captured : Ref[CellId?] = { val: None }
  let v = memo.get_or_else(err => {
    captured.val = Some(err.cell())
    -456
  })

  inspect(v, content="-456")
  inspect(captured.val == Some(memo.id()), content="true")

  meta.in_progress = false
  ignore(rt.pop_tracking())
}

///|
// pull_verify uses MemoData.compute for recomputation.
// This test verifies that stale memo recomputation via pull_verify succeeds.
test "pull_verify: recomputes stale memo via MemoData.compute" {
  let rt = Runtime::new()
  let sig = Signal::new(rt, 0)
  let memo = Memo::new(rt, () => sig.get() + 1)
  // Force first computation to populate cell state
  let _ = rt.read(memo)
  // Trigger re-verification: change sig so the memo is stale
  sig.set(1)
  // pull_verify recomputes via MemoData.compute
  inspect(rt.read(memo), content="2")
}
