///|
// Trigger finish_frame_changed with a Derived cell whose recompute_and_check
// is None — simulates internal state corruption.
test "panic finish_frame_changed: Derived cell with None recompute_and_check aborts" {
  let rt = Runtime::new()
  let sig = Signal::new(rt, 0)
  let memo = Memo::new(rt, fn() { sig.get() + 1 })
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
