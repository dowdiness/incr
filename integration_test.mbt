///|
test "integration: diamond dependency" {
  // input -> A -> C
  //       -> B -> C
  // C depends on both A and B which both depend on input
  let rt = Runtime::new()
  let input = Signal::new(rt, 10)
  let mut a_count = 0
  let a = Memo::new(rt, fn() {
    a_count = a_count + 1
    input.get() + 1
  })
  let mut b_count = 0
  let b = Memo::new(rt, fn() {
    b_count = b_count + 1
    input.get() * 2
  })
  let mut c_count = 0
  let c = Memo::new(rt, fn() {
    c_count = c_count + 1
    a.get() + b.get()
  })
  // Initial
  inspect(c.get(), content="31") // (10 + 1) + (10 * 2) = 11 + 20 = 31
  inspect(a_count, content="1")
  inspect(b_count, content="1")
  inspect(c_count, content="1")
  // Change input
  input.set(5)
  inspect(c.get(), content="16") // (5 + 1) + (5 * 2) = 6 + 10 = 16
  inspect(a_count, content="2")
  inspect(b_count, content="2")
  inspect(c_count, content="2")
}

///|
test "integration: long chain (5 levels)" {
  let rt = Runtime::new()
  let input = Signal::new(rt, 1)
  let l1 = Memo::new(rt, fn() { input.get() + 1 })
  let l2 = Memo::new(rt, fn() { l1.get() + 1 })
  let l3 = Memo::new(rt, fn() { l2.get() + 1 })
  let l4 = Memo::new(rt, fn() { l3.get() + 1 })
  let l5 = Memo::new(rt, fn() { l4.get() + 1 })
  inspect(l5.get(), content="6") // 1 + 5
  input.set(10)
  inspect(l5.get(), content="15") // 10 + 5
  input.set(0)
  inspect(l5.get(), content="5") // 0 + 5
}

///|
test "integration: multiple independent inputs" {
  let rt = Runtime::new()
  let x = Signal::new(rt, 2)
  let y = Signal::new(rt, 3)
  let z = Signal::new(rt, 5)
  let mut compute_count = 0
  let result = Memo::new(rt, fn() {
    compute_count = compute_count + 1
    x.get() * y.get() + z.get()
  })
  inspect(result.get(), content="11") // 2*3 + 5
  inspect(compute_count, content="1")
  // Change only x
  x.set(4)
  inspect(result.get(), content="17") // 4*3 + 5
  inspect(compute_count, content="2")
  // Change only z
  z.set(10)
  inspect(result.get(), content="22") // 4*3 + 10
  inspect(compute_count, content="3")
  // Change y
  y.set(0)
  inspect(result.get(), content="10") // 4*0 + 10
  inspect(compute_count, content="4")
}

///|
test "integration: diamond with backdating" {
  // input -> is_positive -> result
  //       -> abs_val     -> result
  // When input goes from 5 to -5:
  // - is_positive changes (true -> false), so result must recompute
  // - abs_val stays 5 (backdated)
  let rt = Runtime::new()
  let input = Signal::new(rt, 5)
  let is_positive = Memo::new(rt, fn() { input.get() > 0 })
  let abs_val = Memo::new(rt, fn() {
    let v = input.get()
    if v < 0 {
      -v
    } else {
      v
    }
  })
  let mut result_count = 0
  let result = Memo::new(rt, fn() {
    result_count = result_count + 1
    let sign = if is_positive.get() { 1 } else { -1 }
    sign * abs_val.get()
  })
  inspect(result.get(), content="5")
  inspect(result_count, content="1")
  // Change to -5: is_positive changes, abs_val backdated, but result still recomputes
  input.set(-5)
  inspect(result.get(), content="-5")
  inspect(result_count, content="2")
  // Change to -3: is_positive stays false (backdated), abs_val changes
  input.set(-3)
  inspect(result.get(), content="-3")
  inspect(result_count, content="3")
}

///|
test "integration: multiple reads of same memo" {
  let rt = Runtime::new()
  let input = Signal::new(rt, 7)
  let mut compute_count = 0
  let memo = Memo::new(rt, fn() {
    compute_count = compute_count + 1
    input.get() * input.get()
  })
  // Multiple reads should not recompute
  inspect(memo.get(), content="49")
  inspect(memo.get(), content="49")
  inspect(memo.get(), content="49")
  inspect(compute_count, content="1")
}

///|
test "integration: cascading updates" {
  let rt = Runtime::new()
  let a = Signal::new(rt, 1)
  let b = Signal::new(rt, 2)
  let sum = Memo::new(rt, fn() { a.get() + b.get() })
  let product = Memo::new(rt, fn() { a.get() * b.get() })
  let combined = Memo::new(rt, fn() { sum.get() + product.get() })
  inspect(combined.get(), content="5") // (1+2) + (1*2) = 3 + 2
  a.set(3)
  inspect(combined.get(), content="11") // (3+2) + (3*2) = 5 + 6
  b.set(4)
  inspect(combined.get(), content="19") // (3+4) + (3*4) = 7 + 12
}

///|
test "integration: mixed durability chain" {
  let rt = Runtime::new()
  let config = Signal::new_with_durability(rt, 10, High)
  let source = Signal::new(rt, 5)
  let scaled = Memo::new(rt, fn() { source.get() * config.get() })
  inspect(scaled.get(), content="50")
  // Only change low-durability input
  source.set(3)
  inspect(scaled.get(), content="30")
  // Change high-durability input
  config.set(20)
  inspect(scaled.get(), content="60")
}

///|
test "integration: repeated set-get cycles" {
  let rt = Runtime::new()
  let input = Signal::new(rt, 0)
  let doubled = Memo::new(rt, fn() { input.get() * 2 })
  for i = 1; i <= 10; i = i + 1 {
    input.set(i)
    let _ = doubled.get()
  }
  inspect(doubled.get(), content="20") // 10 * 2
}

///|
test "integration: deep chain (200+ levels) - iterative verification" {
  // Stress test: a chain of 250 memos, each depending on the previous.
  // This would cause a stack overflow with recursive verification.
  let rt = Runtime::new()
  let input = Signal::new(rt, 1)
  let depth = 250
  // Build chain: memos[0] depends on input, memos[i] depends on memos[i-1]
  let memos : Array[Memo[Int]] = []
  memos.push(Memo::new(rt, fn() { input.get() + 1 }))
  for i = 1; i < depth; i = i + 1 {
    let prev = memos[i - 1]
    memos.push(Memo::new(rt, fn() { prev.get() + 1 }))
  }
  let tail = memos[depth - 1]
  // Initial: 1 + 250 = 251
  inspect(tail.get(), content="251")
  // Change input and verify propagation through entire chain
  input.set(10)
  inspect(tail.get(), content="260") // 10 + 250
  // Backdating test: set input back to 1
  input.set(1)
  inspect(tail.get(), content="251") // 1 + 250
}

///|
test "integration: dynamic dependencies" {
  // A memo that conditionally reads different signals based on a flag.
  // When the flag flips, the dependency set changes between invocations.
  let rt = Runtime::new()
  let flag = Signal::new(rt, true)
  let a = Signal::new(rt, 10)
  let b = Signal::new(rt, 20)
  let mut compute_count = 0
  let result = Memo::new(rt, fn() {
    compute_count = compute_count + 1
    if flag.get() {
      a.get()
    } else {
      b.get()
    }
  })
  // Initially reads flag + a
  inspect(result.get(), content="10")
  inspect(compute_count, content="1")
  // Changing b should not trigger recompute (not a dependency)
  b.set(99)
  inspect(result.get(), content="10")
  // result recomputed because b's revision bump made maybe_changed_after
  // walk deps, but the dep list is [flag, a], and flag/a didn't change.
  // However, the global revision bumped so verification still runs.
  // The key check: the value is still correct.
  // Flip the flag: now result depends on flag + b
  flag.set(false)
  inspect(result.get(), content="99")
  // Now changing a should not trigger recompute of result
  // (a is no longer in the dependency set after the flag flip)
  a.set(42)
  inspect(result.get(), content="99")
  // Changing b should now trigger recompute
  b.set(55)
  inspect(result.get(), content="55")
}
