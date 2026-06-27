///|
test "integration: push in memo, peek returns values in push order" {
  let rt = @incr.Runtime::Runtime()
  let diags : @incr.Accumulator[String] = @incr.Accumulator::new(
    rt~,
    label="diags",
  )
  let m = @incr.Derived::Derived(rt, () => {
    diags.push("error A")
    diags.push("warn B")
    42
  })
  let _ = read_derived_for_test(m)
  let vs = m.accumulated_peek(diags)
  debug_inspect(vs.length(), content="2")
  inspect(vs[0], content="error A")
  inspect(vs[1], content="warn B")
}

///|
test "integration: multiple memos push to same accumulator, keyed independently" {
  let rt = @incr.Runtime::Runtime()
  let acc : @incr.Accumulator[Int] = @incr.Accumulator::new(rt~)
  let m1 = @incr.Derived::Derived(rt, () => {
    acc.push(100)
    1
  })
  let m2 = @incr.Derived::Derived(rt, () => {
    acc.push(200)
    2
  })
  let _ = read_derived_for_test(m1)
  let _ = read_derived_for_test(m2)
  debug_inspect(m1.accumulated_peek(acc), content="[100]")
  debug_inspect(m2.accumulated_peek(acc), content="[200]")
}

///|
test "integration: stopped pushing invalidates reader" {
  let rt = @incr.Runtime::Runtime()
  let flag = @incr.Signal::Signal(rt, true)
  let acc : @incr.Accumulator[Int] = @incr.Accumulator::new(rt~)
  let producer = @incr.Derived::Derived(rt, () => {
    if flag.get() {
      acc.push(1)
    }
    0
  })
  let consumer = @incr.Derived::Derived(rt, () => {
    producer.accumulated_or_abort(acc).length()
  })
  debug_inspect(read_derived_for_test(consumer), content="1")
  flag.set(false)
  debug_inspect(read_derived_for_test(consumer), content="0")
}

///|
test "integration: accumulated returns Ok on success" {
  let rt = @incr.Runtime::Runtime()
  let acc : @incr.Accumulator[Int] = @incr.Accumulator::new(rt~)
  let m = @incr.Derived::Derived(rt, () => {
    acc.push(5)
    1
  })
  let r = m.accumulated(acc)
  match r {
    Ok(vs) => debug_inspect(vs.length(), content="1")
    Err(_) => fail("expected Ok")
  }
}

///|
test "integration: push outside tracked context raises Failure" {
  let rt = @incr.Runtime::Runtime()
  let acc : @incr.Accumulator[Int] = @incr.Accumulator::new(rt~)
  let caught = try {
    acc.push(1)
    false
  } catch {
    _ => true
  }
  inspect(caught, content="true")
}

///|
test "integration: zero pushes → empty" {
  let rt = @incr.Runtime::Runtime()
  let acc : @incr.Accumulator[Int] = @incr.Accumulator::new(rt~)
  let m = @incr.Derived::Derived(rt, () => 0)
  let _ = read_derived_for_test(m)
  debug_inspect(m.accumulated_peek(acc), content="[]")
}

///|
test "integration: peek on disposed accumulator returns []" {
  let rt = @incr.Runtime::Runtime()
  let acc : @incr.Accumulator[Int] = @incr.Accumulator::new(rt~)
  let m = @incr.Derived::Derived(rt, () => {
    acc.push(1)
    0
  })
  let _ = read_derived_for_test(m)
  acc.dispose()
  debug_inspect(m.accumulated_peek(acc), content="[]")
}

///|
test "integration: accumulated on disposed accumulator raises Failure" {
  let rt = @incr.Runtime::Runtime()
  let acc : @incr.Accumulator[Int] = @incr.Accumulator::new(rt~)
  let m = @incr.Derived::Derived(rt, () => {
    acc.push(1)
    0
  })
  let _ = read_derived_for_test(m)
  acc.dispose()
  let caught = try {
    let _ = m.accumulated(acc)
    false
  } catch {
    _ => true
  }
  inspect(caught, content="true")
}

///|
test "integration: same push-set → backdate (consumer does not recompute)" {
  let rt = @incr.Runtime::Runtime()
  let sig = @incr.Signal::Signal(rt, 0)
  let acc : @incr.Accumulator[Int] = @incr.Accumulator::new(rt~)
  let mut compute_count = 0
  let producer = @incr.Derived::Derived(rt, () => {
    acc.push(42) // same push on every recompute
    sig.get()
  })
  let consumer = @incr.Derived::Derived(rt, () => {
    compute_count = compute_count + 1
    producer.accumulated_or_abort(acc).length()
  })
  let _ = read_derived_for_test(consumer)
  inspect(compute_count, content="1")
  sig.set(1)
  // producer recomputes; push-set unchanged; consumer should backdate.
  let _ = read_derived_for_test(consumer)
  inspect(compute_count, content="1")
}

///|
test "integration: different push-set → invalidate (consumer recomputes)" {
  let rt = @incr.Runtime::Runtime()
  let sig = @incr.Signal::Signal(rt, 0)
  let acc : @incr.Accumulator[Int] = @incr.Accumulator::new(rt~)
  let mut compute_count = 0
  let producer = @incr.Derived::Derived(rt, () => {
    acc.push(sig.get())
    1
  })
  let consumer = @incr.Derived::Derived(rt, () => {
    compute_count = compute_count + 1
    producer.accumulated_or_abort(acc)[0]
  })
  inspect(read_derived_for_test(consumer), content="0")
  inspect(compute_count, content="1")
  sig.set(42)
  inspect(read_derived_for_test(consumer), content="42")
  inspect(compute_count, content="2")
}

///|
test "integration: scope disposal disposes accumulator" {
  let rt = @incr.Runtime::Runtime()
  let scope = @incr.Scope::new(rt)
  let acc : @incr.Accumulator[Int] = scope.accumulator(label="x")
  inspect(acc.is_disposed(), content="false")
  scope.dispose()
  inspect(acc.is_disposed(), content="true")
}

///|
test "integration: diamond — reader reads same accumulator twice, consistent" {
  let rt = @incr.Runtime::Runtime()
  let sig = @incr.Signal::Signal(rt, 10)
  let acc : @incr.Accumulator[Int] = @incr.Accumulator::new(rt~)
  let producer = @incr.Derived::Derived(rt, () => {
    acc.push(sig.get())
    0
  })
  let consumer = @incr.Derived::Derived(rt, () => {
    let a = producer.accumulated_or_abort(acc).length()
    let b = producer.accumulated_or_abort(acc).length()
    a + b
  })
  inspect(read_derived_for_test(consumer), content="2")
}

///|
/// Minimal Database impl mirror of tests/traits_test.mbt TestDb pattern.
struct AccDb {
  rt : @incr.Runtime
}

///|
impl @incr.Database for AccDb with fn runtime(self) {
  self.rt
}

///|
test "integration: create_accumulator via Database helper" {
  let db : AccDb = { rt: @incr.Runtime::Runtime() }
  let acc : @incr.Accumulator[Int] = @incr.create_accumulator(db, label="d")
  debug_inspect(
    acc.label(),
    content=(
      #|Some("d")
    ),
  )
  inspect(acc.is_disposed(), content="false")
}
