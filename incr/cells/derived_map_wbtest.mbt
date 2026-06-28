///|
test "derived_map wb: get_or and get_or_else fallback on cycle error" {
  let rt = Runtime::Runtime()
  let source = Input::Input(rt, 1)
  let by_key = DerivedMap(rt, (key : Int) => source.get() + key)
  inspect(by_key.read_or_abort(1), content="2")

  let inner_cell = by_key.entries.get(1).unwrap()
  let meta = rt.get_memo_data(inner_cell.id())
  // Simulate leaked verifier state and force reverification on next read.
  meta.in_progress = true
  source.set(2)

  inspect(by_key.read_or(1, -10), content="-10")

  let captured : Ref[CellId?] = { val: None }
  inspect(
    by_key.read_or_else(1, err => {
      captured.val = Some(err.cell())
      -11
    }),
    content="-11",
  )
  inspect(captured.val == Some(inner_cell.id()), content="true")

  // Manual cleanup: restore MemoData.in_progress for test isolation.
  meta.in_progress = false
}

///|
test "derived_map wb: clear_cache disposes inner wrappers, not just evicts" {
  let rt = Runtime::Runtime()
  let by_key = DerivedMap(rt, (key : Int) => key + 5)
  ignore(by_key.read_or_abort(1))
  let inner_memo = by_key.entries.get(1).unwrap()
  assert_false(inner_memo.is_disposed())
  by_key.clear_cache()
  assert_true(inner_memo.is_disposed()) // wrapper was disposed, not just evicted
  inspect(by_key.cache_len(), content="0")
  // Re-creating an entry after clear() yields a fresh wrapper that recomputes.
  inspect(by_key.read_or_abort(1), content="6")
  inspect(by_key.cache_len(), content="1")
}
