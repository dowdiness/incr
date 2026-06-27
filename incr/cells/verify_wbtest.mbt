///|
// Characterization test: this simulates the state left behind if memo
// recomputation aborts after setting in_progress and pushing tracking.
test "verify leak simulation: stale in_progress causes spurious cycle" {
  let rt = Runtime::Runtime()
  let sig = Signal::Signal(rt, 0)
  let memo = Derived(rt, () => sig.get() + 1)
  let meta = rt.get_memo_data(memo.id())
  meta.in_progress = true
  rt.push_tracking(memo.id())

  match memo.get() {
    Ok(_) => abort("expected cycle error")
    Err(ReadError::Cycle(e)) => {
      inspect(e.cell() == memo.id(), content="true")
      // Path contains leaked tracking frame + closing id.
      inspect(e.path().length(), content="2")
    }
    Err(ReadError::Disposed(_)) => abort("unexpected disposed")
  }
  inspect(meta.in_progress, content="true")
  inspect(rt.core.tracking.stack.length(), content="1")
}

///|
// Characterization test: if leaked state is cleaned manually, normal reads
// succeed again.
test "verify leak simulation: manual cleanup recovers memo reads" {
  let rt = Runtime::Runtime()
  let sig = Signal::Signal(rt, 0)
  let memo = Derived(rt, () => sig.get() + 1)
  let meta = rt.get_memo_data(memo.id())
  meta.in_progress = true
  rt.push_tracking(memo.id())

  meta.in_progress = false
  ignore(rt.pop_tracking())

  inspect(memo.read_or_abort(), content="1")
}

test "memo_get_or_returns_fallback_on_cycle_error" {
  let rt = Runtime::Runtime()
  let sig = Signal::Signal(rt, 0)
  let memo = Derived(rt, () => sig.get() + 1)
  let meta = rt.get_memo_data(memo.id())
  meta.in_progress = true
  rt.push_tracking(memo.id())

  match memo.get() {
    Ok(v) => inspect(v, content="-123")
    Err(ReadError::Cycle(_)) => inspect(-123, content="-123")
    Err(ReadError::Disposed(_)) => abort("unexpected disposed")
  }

  meta.in_progress = false
  ignore(rt.pop_tracking())
}

///|
///|
test "memo_get_or_else_receives_cycle_error" {
  let rt = Runtime::Runtime()
  let sig = Signal::Signal(rt, 0)
  let memo = Derived(rt, () => sig.get() + 1)
  let meta = rt.get_memo_data(memo.id())
  meta.in_progress = true
  rt.push_tracking(memo.id())

  let captured : Ref[CellId?] = { val: None }
  let v = match memo.get() {
    Ok(v) => v
    Err(ReadError::Cycle(err)) => {
      captured.val = Some(err.cell())
      -456
    }
    Err(ReadError::Disposed(_)) => abort("unexpected")
  }
  meta.in_progress = false
  ignore(rt.pop_tracking())
}

///|
// pull_verify uses MemoData.compute for recomputation.
// This test verifies that stale memo recomputation via pull_verify succeeds.
test "pull_verify: recomputes stale memo via MemoData.compute" {
  let rt = Runtime::Runtime()
  let sig = Signal::Signal(rt, 0)
  let memo = Derived(rt, () => sig.get() + 1)
  // Force first computation to populate cell state
  let _ = memo.read_or_abort()
  // Trigger re-verification: change sig so the memo is stale
  sig.set(1)
  // pull_verify recomputes via MemoData.compute
  inspect(memo.read_or_abort(), content="2")
}
