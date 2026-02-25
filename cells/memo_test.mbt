///|
test "memo: basic computation" {
  let rt = Runtime::new()
  let input = Signal::new(rt, 10)
  let doubled = Memo::new(rt, () => input.get() * 2)
  inspect(doubled.get(), content="20")
}

///|
test "memo: cache hit on second read" {
  let rt = Runtime::new()
  let mut compute_count = 0
  let input = Signal::new(rt, 5)
  let memo = Memo::new(rt, () => {
    compute_count = compute_count + 1
    input.get() + 1
  })
  inspect(memo.get(), content="6")
  inspect(compute_count, content="1")
  // Second get should use cache, not recompute
  inspect(memo.get(), content="6")
  inspect(compute_count, content="1")
}

///|
test "memo: recomputes on input change" {
  let rt = Runtime::new()
  let mut compute_count = 0
  let input = Signal::new(rt, 3)
  let memo = Memo::new(rt, () => {
    compute_count = compute_count + 1
    input.get() * 3
  })
  inspect(memo.get(), content="9")
  inspect(compute_count, content="1")
  input.set(4)
  inspect(memo.get(), content="12")
  inspect(compute_count, content="2")
}

///|
test "memo: chain of two memos" {
  let rt = Runtime::new()
  let input = Signal::new(rt, 2)
  let step1 = Memo::new(rt, () => input.get() + 10)
  let step2 = Memo::new(rt, () => step1.get() * 2)
  inspect(step2.get(), content="24") // (2 + 10) * 2
  input.set(5)
  inspect(step2.get(), content="30") // (5 + 10) * 2
}

///|
test "memo: no recompute when input unchanged" {
  let rt = Runtime::new()
  let mut compute_count = 0
  let input = Signal::new(rt, 7)
  let memo = Memo::new(rt, () => {
    compute_count = compute_count + 1
    input.get()
  })
  inspect(memo.get(), content="7")
  inspect(compute_count, content="1")
  // Set same value — no revision bump
  input.set(7)
  inspect(memo.get(), content="7")
  inspect(compute_count, content="1")
}

///|
test "memo: multiple inputs" {
  let rt = Runtime::new()
  let a = Signal::new(rt, 3)
  let b = Signal::new(rt, 4)
  let sum = Memo::new(rt, () => a.get() + b.get())
  inspect(sum.get(), content="7")
  a.set(10)
  inspect(sum.get(), content="14")
  b.set(20)
  inspect(sum.get(), content="30")
}

///|
test "memo: three-level chain" {
  let rt = Runtime::new()
  let input = Signal::new(rt, 1)
  let l1 = Memo::new(rt, () => input.get() + 1)
  let l2 = Memo::new(rt, () => l1.get() + 1)
  let l3 = Memo::new(rt, () => l2.get() + 1)
  inspect(l3.get(), content="4") // 1 + 1 + 1 + 1
  input.set(10)
  inspect(l3.get(), content="13") // 10 + 1 + 1 + 1
}
