///|
test "backdating: intermediate memo unchanged stops downstream recompute" {
  // Signal -> clamp (caps at 100) -> downstream
  // When signal changes from 50 to 60, clamp still returns the same capped value?
  // No — let's use a clearer example:
  // signal (parity-irrelevant) -> is_even -> downstream
  let rt = Runtime::new()
  let input = Signal::new(rt, 4)
  let mut is_even_count = 0
  let is_even = Memo::new(rt, () => {
    is_even_count = is_even_count + 1
    input.get() % 2 == 0
  })
  let mut downstream_count = 0
  let downstream = Memo::new(rt, () => {
    downstream_count = downstream_count + 1
    if is_even.get() {
      "even"
    } else {
      "odd"
    }
  })
  // Initial computation
  inspect(downstream.get(), content="even")
  inspect(is_even_count, content="1")
  inspect(downstream_count, content="1")
  // Change input from 4 to 6: is_even still true (backdated)
  input.set(6)
  inspect(downstream.get(), content="even")
  // is_even recomputed (its input changed)
  inspect(is_even_count, content="2")
  // downstream should NOT recompute because is_even's value didn't change (backdated)
  inspect(downstream_count, content="1")
}

///|
test "backdating: value actually changes propagates" {
  let rt = Runtime::new()
  let input = Signal::new(rt, 4)
  let mut is_even_count = 0
  let is_even = Memo::new(rt, () => {
    is_even_count = is_even_count + 1
    input.get() % 2 == 0
  })
  let mut downstream_count = 0
  let downstream = Memo::new(rt, () => {
    downstream_count = downstream_count + 1
    if is_even.get() {
      "even"
    } else {
      "odd"
    }
  })
  inspect(downstream.get(), content="even")
  // Change input from 4 to 5: is_even changes from true to false
  input.set(5)
  inspect(downstream.get(), content="odd")
  inspect(is_even_count, content="2")
  inspect(downstream_count, content="2") // downstream DID recompute
}

///|
test "backdating: three-level chain with stable middle" {
  // input -> abs (absolute value) -> doubled
  // Change input from 5 to -5: abs stays 5, doubled should not recompute
  let rt = Runtime::new()
  let input = Signal::new(rt, 5)
  let mut abs_count = 0
  let abs_val = Memo::new(rt, () => {
    abs_count = abs_count + 1
    let v = input.get()
    if v < 0 {
      -v
    } else {
      v
    }
  })
  let mut doubled_count = 0
  let doubled = Memo::new(rt, () => {
    doubled_count = doubled_count + 1
    abs_val.get() * 2
  })
  inspect(doubled.get(), content="10")
  inspect(abs_count, content="1")
  inspect(doubled_count, content="1")
  // Change to -5: abs is still 5 (backdated)
  input.set(-5)
  inspect(doubled.get(), content="10")
  inspect(abs_count, content="2") // abs recomputed
  inspect(doubled_count, content="1") // doubled did NOT recompute
}

///|
test "backdating: multiple changes, some stable some not" {
  let rt = Runtime::new()
  let input = Signal::new(rt, 10)
  let mut clamp_count = 0
  let clamped = Memo::new(rt, () => {
    clamp_count = clamp_count + 1
    let v = input.get()
    if v > 100 {
      100
    } else if v < 0 {
      0
    } else {
      v
    }
  })
  let mut fmt_count = 0
  let formatted = Memo::new(rt, () => {
    fmt_count = fmt_count + 1
    clamped.get()
  })
  inspect(formatted.get(), content="10")
  // Change within range: value changes, downstream recomputes
  input.set(50)
  inspect(formatted.get(), content="50")
  inspect(clamp_count, content="2")
  inspect(fmt_count, content="2")
  // Change from 200 to 300: both above 100, clamp returns 100 both times
  input.set(200)
  inspect(formatted.get(), content="100")
  inspect(clamp_count, content="3")
  inspect(fmt_count, content="3")
  input.set(300)
  inspect(formatted.get(), content="100")
  inspect(clamp_count, content="4")
  inspect(fmt_count, content="3") // backdated: clamped didn't change
}
