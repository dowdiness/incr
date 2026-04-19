///|
test "integration: push in memo, peek returns values in push order" {
  let rt = @incr.Runtime::new()
  let diags : @incr.Accumulator[String] = @incr.Accumulator::new(
    rt~,
    label="diags",
  )
  let m = @incr.Memo::new(rt, () => {
    diags.push("error A")
    diags.push("warn B")
    42
  })
  let _ = rt.read(m)
  let vs = m.accumulated_peek(diags)
  inspect(vs.length(), content="2")
  inspect(vs[0], content="error A")
  inspect(vs[1], content="warn B")
}

///|
test "integration: multiple memos push to same accumulator, keyed independently" {
  let rt = @incr.Runtime::new()
  let acc : @incr.Accumulator[Int] = @incr.Accumulator::new(rt~)
  let m1 = @incr.Memo::new(rt, () => {
    acc.push(100)
    1
  })
  let m2 = @incr.Memo::new(rt, () => {
    acc.push(200)
    2
  })
  let _ = rt.read(m1)
  let _ = rt.read(m2)
  inspect(m1.accumulated_peek(acc), content="[100]")
  inspect(m2.accumulated_peek(acc), content="[200]")
}

///|
test "integration: stopped pushing invalidates reader" {
  let rt = @incr.Runtime::new()
  let flag = @incr.Signal::new(rt, true)
  let acc : @incr.Accumulator[Int] = @incr.Accumulator::new(rt~)
  let producer = @incr.Memo::new(rt, () => {
    if flag.get() {
      acc.push(1)
    }
    0
  })
  let consumer = @incr.Memo::new(rt, () => producer.accumulated(acc).length())
  inspect(rt.read(consumer), content="1")
  flag.set(false)
  inspect(rt.read(consumer), content="0")
}

///|
test "integration: accumulated_result returns Ok on success" {
  let rt = @incr.Runtime::new()
  let acc : @incr.Accumulator[Int] = @incr.Accumulator::new(rt~)
  let m = @incr.Memo::new(rt, () => {
    acc.push(5)
    1
  })
  let r = m.accumulated_result(acc)
  match r {
    Ok(vs) => inspect(vs.length(), content="1")
    Err(_) => fail("expected Ok")
  }
}

///|
test "integration: push outside tracked context raises Failure" {
  let rt = @incr.Runtime::new()
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
  let rt = @incr.Runtime::new()
  let acc : @incr.Accumulator[Int] = @incr.Accumulator::new(rt~)
  let m = @incr.Memo::new(rt, () => 0)
  let _ = rt.read(m)
  inspect(m.accumulated_peek(acc), content="[]")
}

///|
test "integration: peek on disposed accumulator returns []" {
  let rt = @incr.Runtime::new()
  let acc : @incr.Accumulator[Int] = @incr.Accumulator::new(rt~)
  let m = @incr.Memo::new(rt, () => {
    acc.push(1)
    0
  })
  let _ = rt.read(m)
  acc.dispose()
  inspect(m.accumulated_peek(acc), content="[]")
}

///|
test "integration: accumulated on disposed accumulator raises Failure" {
  let rt = @incr.Runtime::new()
  let acc : @incr.Accumulator[Int] = @incr.Accumulator::new(rt~)
  let m = @incr.Memo::new(rt, () => {
    acc.push(1)
    0
  })
  let _ = rt.read(m)
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
  let rt = @incr.Runtime::new()
  let sig = @incr.Signal::new(rt, 0)
  let acc : @incr.Accumulator[Int] = @incr.Accumulator::new(rt~)
  let mut compute_count = 0
  let producer = @incr.Memo::new(rt, () => {
    acc.push(42) // same push on every recompute
    sig.get()
  })
  let consumer = @incr.Memo::new(rt, () => {
    compute_count = compute_count + 1
    producer.accumulated(acc).length()
  })
  let _ = rt.read(consumer)
  inspect(compute_count, content="1")
  sig.set(1)
  // producer recomputes; push-set unchanged; consumer should backdate.
  let _ = rt.read(consumer)
  inspect(compute_count, content="1")
}

///|
test "integration: different push-set → invalidate (consumer recomputes)" {
  let rt = @incr.Runtime::new()
  let sig = @incr.Signal::new(rt, 0)
  let acc : @incr.Accumulator[Int] = @incr.Accumulator::new(rt~)
  let mut compute_count = 0
  let producer = @incr.Memo::new(rt, () => {
    acc.push(sig.get())
    1
  })
  let consumer = @incr.Memo::new(rt, () => {
    compute_count = compute_count + 1
    producer.accumulated(acc)[0]
  })
  inspect(rt.read(consumer), content="0")
  inspect(compute_count, content="1")
  sig.set(42)
  inspect(rt.read(consumer), content="42")
  inspect(compute_count, content="2")
}

///|
test "integration: scope disposal disposes accumulator" {
  let rt = @incr.Runtime::new()
  let scope = @incr.Scope::new(rt)
  let acc : @incr.Accumulator[Int] = scope.accumulator(label="x")
  inspect(acc.is_disposed(), content="false")
  scope.dispose()
  inspect(acc.is_disposed(), content="true")
}

///|
test "integration: diamond — reader reads same accumulator twice, consistent" {
  let rt = @incr.Runtime::new()
  let sig = @incr.Signal::new(rt, 10)
  let acc : @incr.Accumulator[Int] = @incr.Accumulator::new(rt~)
  let producer = @incr.Memo::new(rt, () => {
    acc.push(sig.get())
    0
  })
  let consumer = @incr.Memo::new(rt, () => {
    let a = producer.accumulated(acc).length()
    let b = producer.accumulated(acc).length()
    a + b
  })
  inspect(rt.read(consumer), content="2")
}

///|
/// Minimal Database impl mirror of tests/traits_test.mbt TestDb pattern.
struct AccDb {
  rt : @incr.Runtime

  fn new() -> AccDb
}

///|
fn AccDb::new() -> AccDb {
  { rt: @incr.Runtime::new() }
}

///|
impl @incr.Database for AccDb with runtime(self) {
  self.rt
}

///|
test "integration: create_accumulator via Database helper" {
  let db = AccDb::new()
  let acc : @incr.Accumulator[Int] = @incr.create_accumulator(db, label="d")
  inspect(acc.label(), content="Some(\"d\")")
  inspect(acc.is_disposed(), content="false")
}
