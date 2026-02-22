///|
test "fanout: single signal with many downstream memos" {
  let rt = Runtime::new()
  let input = Signal::new(rt, 10)
  let count = 100
  let memos : Array[Memo[Int]] = []
  let compute_counts : Array[Ref[Int]] = []

  // Create many memos, each depending on the same signal
  for i = 0; i < count; i = i + 1 {
    let counter : Ref[Int] = { val: 0 }
    compute_counts.push(counter)
    let multiplier = i + 1
    memos.push(
      Memo::new(rt, fn() {
        counter.val = counter.val + 1
        input.get() * multiplier
      }),
    )
  }

  // Initial computation: all memos should compute once
  for i = 0; i < count; i = i + 1 {
    let expected = 10 * (i + 1)
    inspect(memos[i].get() == expected, content="true")
    inspect(compute_counts[i].val, content="1")
  }

  // Change input: all memos should recompute exactly once
  input.set(20)
  for i = 0; i < count; i = i + 1 {
    let expected = 20 * (i + 1)
    inspect(memos[i].get() == expected, content="true")
    inspect(compute_counts[i].val, content="2")
  }

  // Set same value: no recomputation (signal same-value optimization)
  input.set(20)
  for i = 0; i < count; i = i + 1 {
    let _ = memos[i].get()
    inspect(compute_counts[i].val, content="2")
  }
}

///|
test "fanout: aggregator memo over many inputs" {
  // Reverse pattern: many signals feeding into one memo
  let rt = Runtime::new()
  let count = 50
  let signals : Array[Signal[Int]] = []

  for i = 0; i < count; i = i + 1 {
    signals.push(Signal::new(rt, i))
  }

  let mut compute_count = 0
  let sum = Memo::new(rt, fn() {
    compute_count = compute_count + 1
    let mut total = 0
    for i = 0; i < count; i = i + 1 {
      total = total + signals[i].get()
    }
    total
  })

  // Initial: sum of 0..49 = 49*50/2 = 1225
  inspect(sum.get(), content="1225")
  inspect(compute_count, content="1")

  // Change one signal: sum increases by 100
  signals[25].set(125) // was 25, now 125 (+100)
  inspect(sum.get(), content="1325")
  inspect(compute_count, content="2")

  // Change another signal
  signals[0].set(1000) // was 0, now 1000 (+1000)
  inspect(sum.get(), content="2325")
  inspect(compute_count, content="3")
}

///|
test "fanout: two-level fanout (signal -> level1 -> level2)" {
  let rt = Runtime::new()
  let input = Signal::new(rt, 5)

  // Level 1: 10 memos directly depending on input
  let level1 : Array[Memo[Int]] = []
  for i = 0; i < 10; i = i + 1 {
    let offset = i
    level1.push(Memo::new(rt, fn() { input.get() + offset }))
  }

  // Level 2: each level1 memo has 5 downstream memos (50 total)
  let level2 : Array[Memo[Int]] = []
  let level2_counts : Array[Ref[Int]] = []
  for i = 0; i < 10; i = i + 1 {
    let parent = level1[i]
    for j = 0; j < 5; j = j + 1 {
      let counter : Ref[Int] = { val: 0 }
      level2_counts.push(counter)
      let mult = j + 1
      level2.push(
        Memo::new(rt, fn() {
          counter.val = counter.val + 1
          parent.get() * mult
        }),
      )
    }
  }

  // Verify initial values
  // level1[2] = 5 + 2 = 7, level2[2*5 + 3] = level2[13] = 7 * 4 = 28
  inspect(level2[13].get(), content="28")
  inspect(level2_counts[13].val, content="1")

  // Change input
  input.set(10)
  // level1[2] = 10 + 2 = 12, level2[13] = 12 * 4 = 48
  inspect(level2[13].get(), content="48")
  inspect(level2_counts[13].val, content="2")
}
