///|
test "integration: debug why memo recomputed" {
  let rt = Runtime::new()
  let x = Signal::new(rt, 10)
  let y = Signal::new(rt, 20)
  let sum = Memo::new(rt, fn() { x.get() + y.get() })

  sum.get() |> ignore
  let initial_verified = sum.verified_at()

  // Same value - backdating means no effective change
  x.set(10)
  sum.get() |> ignore
  inspect(sum.verified_at() == initial_verified, content="true")

  // Different value - should trigger recomputation
  y.set(30)
  sum.get() |> ignore
  inspect(sum.verified_at().value > initial_verified.value, content="true")

  // Identify which dependency caused recomputation
  let mut found_culprit = false
  for dep_id in sum.dependencies() {
    match rt.cell_info(dep_id) {
      Some(info) =>
        if info.changed_at.value > initial_verified.value {
          // Found it: y's changed_at is after initial verification
          inspect(dep_id == y.id(), content="true")
          found_culprit = true
        }
      None => ()
    }
  }
  inspect(found_culprit, content="true")
}

///|
test "integration: analyze dependency chain" {
  let rt = Runtime::new()
  let input = Signal::new(rt, 5)
  let step1 = Memo::new(rt, fn() { input.get() * 2 })
  let step2 = Memo::new(rt, fn() { step1.get() + 10 })
  let step3 = Memo::new(rt, fn() { step2.get() * 3 })

  step3.get() |> ignore

  // Verify dependency chain
  inspect(step3.dependencies().contains(step2.id()), content="true")
  inspect(step2.dependencies().contains(step1.id()), content="true")
  inspect(step1.dependencies().contains(input.id()), content="true")

  // Verify no cross-dependencies
  inspect(step3.dependencies().contains(input.id()), content="false")
  inspect(step3.dependencies().contains(step1.id()), content="false")
}

///|
test "integration: diamond dependency has no duplicates" {
  let rt = Runtime::new()
  let input = Signal::new(rt, 10)
  let left = Memo::new(rt, fn() { input.get() + 1 })
  let right = Memo::new(rt, fn() { input.get() + 2 })
  let merge = Memo::new(rt, fn() { left.get() + right.get() })

  merge.get() |> ignore

  // Merge depends on left and right
  let merge_deps = merge.dependencies()
  inspect(merge_deps.contains(left.id()), content="true")
  inspect(merge_deps.contains(right.id()), content="true")

  // But input appears only once in left's and right's dependencies
  let left_deps = left.dependencies()
  let right_deps = right.dependencies()

  let mut input_count_left = 0
  for dep in left_deps {
    if dep == input.id() {
      input_count_left = input_count_left + 1
    }
  }
  inspect(input_count_left, content="1")

  let mut input_count_right = 0
  for dep in right_deps {
    if dep == input.id() {
      input_count_right = input_count_right + 1
    }
  }
  inspect(input_count_right, content="1")
}

///|
test "integration: understanding backdating with introspection" {
  let rt = Runtime::new()
  let input = Signal::new(rt, 5)
  // A memo that produces the same output for different inputs (absolute value stays same)
  let abs_value = Memo::new(rt, fn() {
    let val = input.get()
    if val < 0 {
      -val
    } else {
      val
    }
  })

  abs_value.get() |> ignore
  let old_changed_at = abs_value.changed_at()
  let old_verified_at = abs_value.verified_at()

  // Change input from 5 to -5: different input, same output (5)
  input.set(-5)
  abs_value.get() |> ignore

  // Backdating: changed_at didn't advance because output is still 5
  inspect(abs_value.changed_at() == old_changed_at, content="true")

  // But verified_at did advance (we did verify it's up to date)
  inspect(abs_value.verified_at().value > old_verified_at.value, content="true")
}
