///|
test "Accumulator::new allocates monotonic slot id" {
  let rt = Runtime::new()
  let a : Accumulator[Int] = Accumulator::new(rt~, label="a")
  let b : Accumulator[Int] = Accumulator::new(rt~, label="b")
  inspect(a.id().id < b.id().id, content="true")
  inspect(a.label(), content="Some(\"a\")")
  inspect(a.is_disposed(), content="false")
}

///|
test "Accumulator::dispose is idempotent and flips is_disposed" {
  let rt = Runtime::new()
  let a : Accumulator[Int] = Accumulator::new(rt~, label="acc")
  inspect(a.is_disposed(), content="false")
  a.dispose()
  inspect(a.is_disposed(), content="true")
  a.dispose() // idempotent — no panic
  inspect(a.is_disposed(), content="true")
}

///|
test "Accumulator::dispose does not reuse slot id" {
  let rt = Runtime::new()
  let a : Accumulator[Int] = Accumulator::new(rt~)
  let first_id = a.id()
  a.dispose()
  let b : Accumulator[Int] = Accumulator::new(rt~)
  inspect(b.id() != first_id, content="true")
  inspect(b.id().id > first_id.id, content="true")
}

///|
test "Accumulator::push outside tracked context raises Failure" {
  let rt = Runtime::new()
  let a : Accumulator[Int] = Accumulator::new(rt~)
  let caught = try {
    a.push(42)
    false
  } catch {
    _ => true
  }
  inspect(caught, content="true")
}

///|
test "Accumulator::push inside memo compute stages value" {
  let rt = Runtime::new()
  let a : Accumulator[Int] = Accumulator::new(rt~, label="diags")
  let memo = Memo::new(rt, () => {
    a.push(1)
    a.push(2)
    99
  })
  // Trigger first compute via ensure_computed_untracked (buffer visible
  // without reading through tracked get()).
  let _ = rt.ensure_computed_untracked(memo.id())
  // Buffer contains pushed values, keyed by memo's cell_id
  match a.per_memo.get(memo.id()) {
    Some(vs) => {
      inspect(vs.length(), content="2")
      inspect(vs[0], content="1")
      inspect(vs[1], content="2")
    }
    None => fail("expected buffer to contain pushes")
  }
}

///|
test "Accumulator::push to disposed accumulator raises Failure" {
  let rt = Runtime::new()
  let a : Accumulator[Int] = Accumulator::new(rt~)
  a.dispose()
  let memo = Memo::new(rt, () => {
    a.push(42)
    1
  })
  let caught = try {
    let _ = rt.ensure_computed_untracked(memo.id())
    false
  } catch {
    _ => true
  }
  inspect(caught, content="true")
}

///|
test "accumulator: same push-set across recomputes → push_revised_at unchanged" {
  let rt = Runtime::new()
  let sig = Signal::new(rt, 0)
  let a : Accumulator[Int] = Accumulator::new(rt~)
  let m = Memo::new(rt, () => {
    a.push(1)
    a.push(2)
    sig.get()
  })
  let _ = rt.ensure_computed_untracked(m.id())
  let rev1 = match a.push_revised_at.get(m.id()) {
    Some(r) => r
    None => Revision::initial()
  }
  // Trigger recompute with same push set
  sig.set(1)
  let _ = rt.ensure_computed_untracked(m.id())
  let rev2 = match a.push_revised_at.get(m.id()) {
    Some(r) => r
    None => Revision::initial()
  }
  inspect(rev1 == rev2, content="true")
}

///|
test "accumulator: different push-set across recomputes → push_revised_at bumps" {
  let rt = Runtime::new()
  let sig = Signal::new(rt, 0)
  let a : Accumulator[Int] = Accumulator::new(rt~)
  let m = Memo::new(rt, () => {
    a.push(sig.get())
    1
  })
  let _ = rt.ensure_computed_untracked(m.id())
  let rev1 = match a.push_revised_at.get(m.id()) {
    Some(r) => r
    None => Revision::initial()
  }
  sig.set(99)
  let _ = rt.ensure_computed_untracked(m.id())
  let rev2 = match a.push_revised_at.get(m.id()) {
    Some(r) => r
    None => Revision::initial()
  }
  inspect(rev2 > rev1, content="true")
}

///|
test "accumulator: ON_ABORT restores prior buffer on raised compute" {
  let rt = Runtime::new()
  let should_fail = Signal::new(rt, false)
  let a : Accumulator[Int] = Accumulator::new(rt~)
  let m : Memo[Int] = Memo::new(rt, () => {
    a.push(1)
    if should_fail.get() {
      fail("boom")
    }
    99
  })
  let _ = rt.ensure_computed_untracked(m.id())
  let first_buf = a.per_memo.get(m.id()).unwrap()
  inspect(first_buf.length(), content="1")
  // Trigger a failing recompute
  should_fail.set(true)
  let caught = try {
    let _ = rt.ensure_computed_untracked(m.id())
    false
  } catch {
    _ => true
  }
  inspect(caught, content="true")
  // Buffer restored to pre-recompute state — still contains the one push
  let restored_buf = a.per_memo.get(m.id()).unwrap()
  inspect(restored_buf.length(), content="1")
  inspect(restored_buf[0], content="1")
}
