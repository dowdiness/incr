///|
test "memo: basic computation" {
  let rt = Runtime::Runtime()
  let input = Signal::Signal(rt, 10)
  let doubled = Memo::Memo(rt, () => input.get() * 2)
  inspect(rt.read(doubled), content="20")
}

///|
test "memo: cache hit on second read" {
  let rt = Runtime::Runtime()
  let mut compute_count = 0
  let input = Signal::Signal(rt, 5)
  let memo = Memo::Memo(rt, () => {
    compute_count = compute_count + 1
    input.get() + 1
  })
  inspect(rt.read(memo), content="6")
  inspect(compute_count, content="1")
  // Second get should use cache, not recompute
  inspect(rt.read(memo), content="6")
  inspect(compute_count, content="1")
}

///|
test "memo: recomputes on input change" {
  let rt = Runtime::Runtime()
  let mut compute_count = 0
  let input = Signal::Signal(rt, 3)
  let memo = Memo::Memo(rt, () => {
    compute_count = compute_count + 1
    input.get() * 3
  })
  inspect(rt.read(memo), content="9")
  inspect(compute_count, content="1")
  input.set(4)
  inspect(rt.read(memo), content="12")
  inspect(compute_count, content="2")
}

///|
test "memo: chain of two memos" {
  let rt = Runtime::Runtime()
  let input = Signal::Signal(rt, 2)
  let step1 = Memo::Memo(rt, () => input.get() + 10)
  let step2 = Memo::Memo(rt, () => step1.get() * 2)
  inspect(rt.read(step2), content="24") // (2 + 10) * 2
  input.set(5)
  inspect(rt.read(step2), content="30") // (5 + 10) * 2
}

///|
test "memo: no recompute when input unchanged" {
  let rt = Runtime::Runtime()
  let mut compute_count = 0
  let input = Signal::Signal(rt, 7)
  let memo = Memo::Memo(rt, () => {
    compute_count = compute_count + 1
    input.get()
  })
  inspect(rt.read(memo), content="7")
  inspect(compute_count, content="1")
  // Set same value — no revision bump
  input.set(7)
  inspect(rt.read(memo), content="7")
  inspect(compute_count, content="1")
}

///|
test "memo: multiple inputs" {
  let rt = Runtime::Runtime()
  let a = Signal::Signal(rt, 3)
  let b = Signal::Signal(rt, 4)
  let sum = Memo::Memo(rt, () => a.get() + b.get())
  inspect(rt.read(sum), content="7")
  a.set(10)
  inspect(rt.read(sum), content="14")
  b.set(20)
  inspect(rt.read(sum), content="30")
}

///|
test "memo: three-level chain" {
  let rt = Runtime::Runtime()
  let input = Signal::Signal(rt, 1)
  let l1 = Memo::Memo(rt, () => input.get() + 1)
  let l2 = Memo::Memo(rt, () => l1.get() + 1)
  let l3 = Memo::Memo(rt, () => l2.get() + 1)
  inspect(rt.read(l3), content="4") // 1 + 1 + 1 + 1
  input.set(10)
  inspect(rt.read(l3), content="13") // 10 + 1 + 1 + 1
}

///|
test "panic cross-runtime: Signal::get aborts when read inside a memo on a different runtime" {
  // Signal::get detects that the active computation belongs to a different
  // runtime and aborts rather than silently recording no dependency.
  let rt_a = Runtime::Runtime()
  let rt_b = Runtime::Runtime()
  let sig_b = Signal::Signal(rt_b, 10)
  let memo_a = Memo::Memo(rt_a, () => sig_b.get())
  let _ = rt_a.read(memo_a) // aborts: sig_b is on rt_b, memo_a computes on rt_a
}

///|
test "panic cross-runtime: Memo::get aborts when read inside a memo on a different runtime" {
  let rt_a = Runtime::Runtime()
  let rt_b = Runtime::Runtime()
  let memo_b = Memo::Memo(rt_b, () => 42)
  let memo_a = Memo::Memo(rt_a, () => memo_b.get())
  let _ = rt_a.read(memo_a) // aborts: memo_b is on rt_b, memo_a computes on rt_a
}

///|
test "panic Memo::get() outside tracked context" {
  let rt = Runtime::Runtime()
  let s = Signal::Signal(rt, 10)
  let m = Memo::Memo(rt, () => s.get() * 2)
  ignore(m.get())
}

///|
test "panic HybridMemo::get() outside tracked context" {
  let rt = Runtime::Runtime()
  let s = Signal::Signal(rt, 10)
  let h = HybridMemo::HybridMemo(rt, () => s.get() * 2)
  ignore(h.get())
}

///|
test "panic Reactive::get() outside tracked context" {
  let rt = Runtime::Runtime()
  let s = Signal::Signal(rt, 10)
  let r = Reactive::new(rt, () => s.get())
  ignore(r.get())
}

///|
test "Memo::get() inside tracked context succeeds" {
  let rt = Runtime::Runtime()
  let s = Signal::Signal(rt, 10)
  let m = Memo::Memo(rt, () => s.get() * 2)
  let m2 = Memo::Memo(rt, () => m.get() + 1)
  inspect(rt.read(m2), content="21")
}

///|
test "Signal::peek() reads without tracking" {
  let rt = Runtime::Runtime()
  let s = Signal::Signal(rt, 42)
  // peek works from outside tracked context
  inspect(s.peek(), content="42")
  // peek does not record dependency
  let m = Memo::Memo(rt, () => {
    ignore(s.peek())
    0
  })
  ignore(rt.read(m))
  inspect(m.dependencies().length(), content="0")
}

///|
test "TrackedCell::peek() reads without tracking" {
  let rt = Runtime::Runtime()
  let tc = TrackedCell::TrackedCell(rt, 99)
  inspect(tc.peek(), content="99")
  tc.set(100)
  inspect(tc.peek(), content="100")
}
