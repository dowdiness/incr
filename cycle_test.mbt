///|
test "panic cycle on initial get: direct self-referencing memo aborts" {
  let rt = Runtime::new()
  // Create a memo that references itself — this creates a cycle
  let memo_ref : Ref[Memo[Int]?] = { val: None }
  let memo = Memo::new(rt, fn() {
    match memo_ref.val {
      Some(m) => m.get() + 1
      None => 0
    }
  })
  memo_ref.val = Some(memo)
  // First get() enters force_recompute(), then re-enters force_recompute() via m.get().
  // The second entry must abort with cycle detection rather than recurse indefinitely.
  let _ = memo.get()

}

///|
test "panic cycle on initial get: mutual recursion between two memos aborts" {
  let rt = Runtime::new()
  let memo_b_ref : Ref[Memo[Int]?] = { val: None }
  let memo_a : Memo[Int] = Memo::new(rt, fn() {
    match memo_b_ref.val {
      Some(b) => b.get() + 1
      None => 0
    }
  })
  let memo_b = Memo::new(rt, fn() { memo_a.get() + 1 })
  memo_b_ref.val = Some(memo_b)
  // First get() of memo_a reaches memo_b.get(), which re-enters memo_a.get().
  // This must abort immediately via the in-progress recompute guard.
  let _ = memo_a.get()

}
