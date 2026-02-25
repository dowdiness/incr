///|
test "memo_map wb: get_or and get_or_else fallback on cycle error" {
  let rt = Runtime::new()
  let source = Signal::new(rt, 1)
  let by_key = MemoMap::new(rt, (key : Int) => source.get() + key)
  inspect(by_key.get(1), content="2")

  let memo = by_key.entries.get(1).unwrap()
  let meta = rt.get_cell(memo.id())
  // Simulate leaked verifier state and force reverification on next read.
  meta.in_progress = true
  source.set(2)

  inspect(by_key.get_or(1, -10), content="-10")

  let captured : Ref[CellId?] = { val: None }
  inspect(
    by_key.get_or_else(1, err => {
      captured.val = Some(err.cell())
      -11
    }),
    content="-11",
  )
  inspect(captured.val == Some(memo.id()), content="true")

  // Manual cleanup for test isolation.
  meta.in_progress = false
}
