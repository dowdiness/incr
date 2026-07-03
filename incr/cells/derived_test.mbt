///|
test "derived: basic computation" {
  let rt = Runtime::Runtime()
  let input = Input::Input(rt, 10)
  let doubled = Derived::Derived(rt, () => input.get() * 2)
  inspect(doubled.read_or_abort(), content="20")
}

///|
test "derived: cache hit on second read" {
  let rt = Runtime::Runtime()
  let mut compute_count = 0
  let input = Input::Input(rt, 5)
  let d = Derived::Derived(rt, () => {
    compute_count = compute_count + 1
    input.get() + 1
  })
  inspect(d.read_or_abort(), content="6")
  inspect(compute_count, content="1")
  // Second get should use cache, not recompute
  inspect(d.read_or_abort(), content="6")
  inspect(compute_count, content="1")
}

///|
test "derived: recomputes on input change" {
  let rt = Runtime::Runtime()
  let mut compute_count = 0
  let input = Input::Input(rt, 3)
  let d = Derived::Derived(rt, () => {
    compute_count = compute_count + 1
    input.get() * 3
  })
  inspect(d.read_or_abort(), content="9")
  inspect(compute_count, content="1")
  input.set(4)
  inspect(d.read_or_abort(), content="12")
  inspect(compute_count, content="2")
}

///|
test "derived: chain of two" {
  let rt = Runtime::Runtime()
  let input = Input::Input(rt, 2)
  let step1 = Derived::Derived(rt, () => input.get() + 10)
  let step2 = Derived::Derived(rt, () => step1.get_or_abort() * 2)
  inspect(step2.read_or_abort(), content="24") // (2 + 10) * 2
  input.set(5)
  inspect(step2.read_or_abort(), content="30") // (5 + 10) * 2
}

///|
test "derived: no recompute when input unchanged" {
  let rt = Runtime::Runtime()
  let mut compute_count = 0
  let input = Input::Input(rt, 7)
  let d = Derived::Derived(rt, () => {
    compute_count = compute_count + 1
    input.get()
  })
  inspect(d.read_or_abort(), content="7")
  inspect(compute_count, content="1")
  // Set same value — no revision bump
  input.set(7)
  inspect(d.read_or_abort(), content="7")
  inspect(compute_count, content="1")
}

///|
test "derived: multiple inputs" {
  let rt = Runtime::Runtime()
  let a = Input::Input(rt, 3)
  let b = Input::Input(rt, 4)
  let sum = Derived::Derived(rt, () => a.get() + b.get())
  inspect(sum.read_or_abort(), content="7")
  a.set(10)
  inspect(sum.read_or_abort(), content="14")
  b.set(20)
  inspect(sum.read_or_abort(), content="30")
}

///|
test "derived: three-level chain" {
  let rt = Runtime::Runtime()
  let input = Input::Input(rt, 1)
  let l1 = Derived::Derived(rt, () => input.get() + 1)
  let l2 = Derived::Derived(rt, () => l1.get_or_abort() + 1)
  let l3 = Derived::Derived(rt, () => l2.get_or_abort() + 1)
  inspect(l3.read_or_abort(), content="4") // 1 + 1 + 1 + 1
  input.set(10)
  inspect(l3.read_or_abort(), content="13") // 10 + 1 + 1 + 1
}

///|
test "panic cross-runtime: Input::get aborts when read inside a derived on a different runtime" {
  // Input::get detects that the active computation belongs to a different
  // runtime and aborts rather than silently recording no dependency.
  let rt_a = Runtime::Runtime()
  let rt_b = Runtime::Runtime()
  let sig_b = Input::Input(rt_b, 10)
  let d_a = Derived::Derived(rt_a, () => sig_b.get())
  let _ = d_a.read_or_abort() // aborts: sig_b is on rt_b, d_a computes on rt_a
}

///|
test "panic cross-runtime: Derived::get aborts when read inside a derived on a different runtime" {
  let rt_a = Runtime::Runtime()
  let rt_b = Runtime::Runtime()
  let d_b = Derived::Derived(rt_b, () => 42)
  let d_a = Derived::Derived(rt_a, () => d_b.get_or_abort())
  let _ = d_a.read_or_abort() // aborts: d_b is on rt_b, d_a computes on rt_a
}

///|
test "panic Derived::get() outside tracked context" {
  let rt = Runtime::Runtime()
  let s = Input::Input(rt, 10)
  let d = Derived::Derived(rt, () => s.get() * 2)
  ignore(d.get_or_abort())
}

///|
test "panic ReachableDerived::get() outside tracked context" {
  let rt = Runtime::Runtime()
  let s = Input::Input(rt, 10)
  let rd = ReachableDerived::ReachableDerived(rt, () => s.get() * 2)
  ignore(rd.get_or_abort())
}

///|
test "panic Reactive::get() outside tracked context" {
  let rt = Runtime::Runtime()
  let s = Input::Input(rt, 10)
  let r = EagerDerived::EagerDerived(rt, () => s.get())
  ignore(r.get())
}

///|
test "Derived::get() inside tracked context succeeds" {
  let rt = Runtime::Runtime()
  let s = Input::Input(rt, 10)
  let d = Derived::Derived(rt, () => s.get() * 2)
  let d2 = Derived::Derived(rt, () => d.get_or_abort() + 1)
  inspect(d2.read_or_abort(), content="21")
}

///|
test "Input::peek() reads without tracking" {
  let rt = Runtime::Runtime()
  let s = Input::Input(rt, 42)
  // peek works from outside tracked context
  inspect(s.peek(), content="42")
  // peek does not record dependency
  let d = Derived::Derived(rt, () => {
    ignore(s.peek())
    0
  })
  ignore(d.read_or_abort())
  inspect(d.dependencies().length(), content="0")
}

///|
test "InputField::peek() reads without tracking" {
  let rt = Runtime::Runtime()
  let tc = InputField::InputField(rt, 99)
  inspect(tc.peek(), content="99")
  tc.set(100)
  inspect(tc.peek(), content="100")
}
