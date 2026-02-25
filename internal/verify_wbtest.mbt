///|
// Characterization test: this simulates the state left behind if memo
// recomputation aborts after setting in_progress and pushing tracking.
test "verify leak simulation: stale in_progress causes spurious cycle" {
  let rt = Runtime::new()
  let sig = Signal::new(rt, 0)
  let memo = Memo::new(rt, () => sig.get() + 1)
  let meta = rt.get_cell(memo.id())
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
  inspect(rt.tracking_stack.length(), content="1")
}

///|
// Characterization test: if leaked state is cleaned manually, normal reads
// succeed again.
test "verify leak simulation: manual cleanup recovers memo reads" {
  let rt = Runtime::new()
  let sig = Signal::new(rt, 0)
  let memo = Memo::new(rt, () => sig.get() + 1)
  let meta = rt.get_cell(memo.id())
  meta.in_progress = true
  rt.push_tracking(memo.id())

  meta.in_progress = false
  ignore(rt.pop_tracking())

  match memo.get_result() {
    Ok(v) => inspect(v, content="1")
    Err(_) => abort("expected successful get_result")
  }
}

///|
test "memo_get_or_returns_fallback_on_cycle_error" {
  let rt = Runtime::new()
  let sig = Signal::new(rt, 0)
  let memo = Memo::new(rt, () => sig.get() + 1)
  let meta = rt.get_cell(memo.id())
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
  let meta = rt.get_cell(memo.id())
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
// Trigger finish_frame_changed with a Derived cell whose recompute_and_check
// is None — simulates internal state corruption.
test "panic finish_frame_changed: Derived cell with None recompute_and_check aborts" {
  let rt = Runtime::new()
  let sig = Signal::new(rt, 0)
  let memo = Memo::new(rt, () => sig.get() + 1)
  // Force first computation to populate cell state
  let _ = memo.get_result()
  // Corrupt internal state: clear the type-erased recompute closure
  let meta = rt.get_cell(memo.id())
  meta.recompute_and_check = None
  // Trigger a re-verification: change sig so the memo is stale
  sig.set(1)
  // get_result calls maybe_changed_after which calls finish_frame_changed
  // with the corrupted cell — must abort
  let _ = memo.get_result()
}
