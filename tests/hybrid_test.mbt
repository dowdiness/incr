///|
test "hybrid: basic get and update" {
  let rt = Runtime::new()
  let s = Signal::new(rt, 1)
  let h = @incr.HybridMemo::new(rt, () => s.get() * 2)
  inspect(h.get(), content="2")
  s.set(5)
  inspect(h.get(), content="10")
}

///|
test "hybrid: create_hybrid_memo helper" {
  let db = TestDb::new()
  let s = @incr.create_signal(db, 3)
  let h = @incr.create_hybrid_memo(db, () => s.get() + 1)
  inspect(h.get(), content="4")
  s.set(10)
  inspect(h.get(), content="11")
}

///|
test "hybrid: is_up_to_date before first get returns false" {
  let rt = Runtime::new()
  let s = Signal::new(rt, 1)
  let h = @incr.HybridMemo::new(rt, () => s.get())
  // Never-computed memo has no cached value — must not be considered up-to-date.
  inspect(h.is_up_to_date(), content="false")
}

///|
test "hybrid: is_up_to_date via Readable" {
  let rt = Runtime::new()
  let s = Signal::new(rt, 1)
  let h = @incr.HybridMemo::new(rt, () => s.get())
  let _ = h.get()
  inspect(h.is_up_to_date(), content="true")
  s.set(2)
  inspect(h.is_up_to_date(), content="false")
  let _ = h.get()
  inspect(h.is_up_to_date(), content="true")
}

///|
test "hybrid: unchanged value does not propagate (backdating)" {
  // If the hybrid memo recomputes to the same value, downstream memos skip.
  let rt = Runtime::new()
  let s = Signal::new(rt, 2)
  let h = @incr.HybridMemo::new(rt, () => s.get() % 2) // always 0
  let mut count = 0
  let m = Memo::new(rt, () => {
    count = count + 1
    h.get() + 1
  })
  inspect(m.get(), content="1")
  inspect(count, content="1")
  s.set(4) // h still computes 0 → backdated → m should not recompute
  inspect(m.get(), content="1")
  inspect(count, content="1") // no recompute
}

///|
test "hybrid: diamond — signal → two hybrids → memo" {
  let rt = Runtime::new()
  let s = Signal::new(rt, 3)
  let h1 = @incr.HybridMemo::new(rt, () => s.get() + 1)
  let h2 = @incr.HybridMemo::new(rt, () => s.get() * 2)
  let mut count = 0
  let m = Memo::new(rt, () => {
    count = count + 1
    h1.get() + h2.get()
  })
  inspect(m.get(), content="10") // (3+1) + (3*2) = 4 + 6 = 10
  inspect(count, content="1")
  s.set(5)
  inspect(m.get(), content="16") // (5+1) + (5*2) = 6 + 10 = 16
  inspect(count, content="2")
}

///|
test "hybrid: batch update — single revision" {
  let rt = Runtime::new()
  let x = Signal::new(rt, 1)
  let y = Signal::new(rt, 2)
  let mut count = 0
  let h = @incr.HybridMemo::new(rt, () => {
    count = count + 1
    x.get() + y.get()
  })
  inspect(h.get(), content="3")
  inspect(count, content="1")
  rt.batch(fn() {
    x.set(10)
    y.set(20)
  })
  inspect(h.get(), content="30")
  inspect(count, content="2") // only one recompute despite two signal changes
}

///|
test "hybrid: chained hybrids" {
  let rt = Runtime::new()
  let s = Signal::new(rt, 1)
  let h1 = @incr.HybridMemo::new(rt, () => s.get() + 1)
  let h2 = @incr.HybridMemo::new(rt, () => h1.get() * 10)
  inspect(h2.get(), content="20")
  s.set(2)
  inspect(h2.get(), content="30")
}

///|
test "hybrid: hybrid as dep of memo — pull chain" {
  let rt = Runtime::new()
  let s = Signal::new(rt, 1)
  let h = @incr.HybridMemo::new(rt, () => s.get() * 2)
  let mut count = 0
  let m = Memo::new(rt, () => {
    count = count + 1
    h.get() + 1
  })
  inspect(m.get(), content="3")
  inspect(count, content="1")
  s.set(3)
  inspect(m.get(), content="7")
  inspect(count, content="2")
}
