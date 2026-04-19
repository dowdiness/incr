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
test "accumulated_peek: returns pushed values in order" {
  let rt = Runtime::new()
  let a : Accumulator[Int] = Accumulator::new(rt~)
  let m = Memo::new(rt, () => {
    a.push(10)
    a.push(20)
    a.push(30)
    0
  })
  let _ = rt.ensure_computed_untracked(m.id())
  let vs = m.accumulated_peek(a)
  inspect(vs.length(), content="3")
  inspect(vs[0], content="10")
  inspect(vs[2], content="30")
}

///|
test "accumulated_peek: returns [] for disposed accumulator" {
  let rt = Runtime::new()
  let a : Accumulator[Int] = Accumulator::new(rt~)
  let m = Memo::new(rt, () => {
    a.push(1)
    0
  })
  let _ = rt.ensure_computed_untracked(m.id())
  a.dispose()
  inspect(m.accumulated_peek(a), content="[]")
}

///|
test "accumulated_peek: returns defensive copy" {
  let rt = Runtime::new()
  let a : Accumulator[Int] = Accumulator::new(rt~)
  let m = Memo::new(rt, () => {
    a.push(1)
    0
  })
  let _ = rt.ensure_computed_untracked(m.id())
  let vs = m.accumulated_peek(a)
  vs.push(999) // mutating returned array
  // Subsequent peek unaffected
  let vs2 = m.accumulated_peek(a)
  inspect(vs2.length(), content="1")
}

///|
test "accumulated: tracked read inside memo stages synthetic dep" {
  let rt = Runtime::new()
  let a : Accumulator[Int] = Accumulator::new(rt~)
  let producer = Memo::new(rt, () => {
    a.push(42)
    1
  })
  let consumer = Memo::new(rt, () => producer.accumulated(a).length())
  let _ = rt.ensure_computed_untracked(consumer.id())
  inspect(rt.read(consumer), content="1")
  // Consumer's MemoData should have a synthetic read entry for (a.slot_id, producer.cell_id)
  let data = rt.get_memo_data(consumer.id())
  let key = (a.slot_id, producer.id())
  inspect(data.accumulator_reads.contains(key), content="true")
}

///|
test "accumulated: raises Failure on disposed accumulator" {
  let rt = Runtime::new()
  let a : Accumulator[Int] = Accumulator::new(rt~)
  let producer = Memo::new(rt, () => 1)
  a.dispose()
  let caught = try {
    let _ = producer.accumulated(a)
    false
  } catch {
    _ => true
  }
  inspect(caught, content="true")
}

///|
test "accumulated_result: Ok on success" {
  let rt = Runtime::new()
  let a : Accumulator[Int] = Accumulator::new(rt~)
  let p = Memo::new(rt, () => {
    a.push(5)
    0
  })
  let r = p.accumulated_result(a)
  match r {
    Ok(vs) => inspect(vs.length(), content="1")
    Err(_) => fail("expected Ok")
  }
}

///|
/// Task 14 guard: verify the durability fast-path is skipped when a memo has
/// non-empty accumulator_reads. Directly asserted via whitebox inspection —
/// end-to-end invalidation requires Task 15's synthetic dep check.
test "durability shortcut: bypassed when memo has accumulator_reads" {
  let rt = Runtime::new()
  let s = Signal::new(rt, 0)
  let a : Accumulator[Int] = Accumulator::new(rt~)
  let producer = Memo::new(rt, () => {
    a.push(s.get())
    1
  })
  let consumer = Memo::new(rt, () => producer.accumulated(a).length())
  // Force first read; populates consumer.accumulator_reads.
  let _ = rt.read(consumer)
  let consumer_data = rt.get_memo_data(consumer.id())
  inspect(consumer_data.accumulator_reads.is_empty(), content="false")
  // Bump revision; consumer.verified_at < current_revision.
  s.set(42)
  // A second read must not crash — the bypass opens the dep-walk path.
  // Task 15 will make this read see the new push-set; Task 14 just ensures
  // pull_verify doesn't short-circuit inappropriately.
  let _ = rt.read(consumer)
}

///|
test "synthetic dep check: reader invalidates when producer's push_revised_at bumps" {
  let rt = Runtime::new()
  let s = Signal::new(rt, 1)
  let a : Accumulator[Int] = Accumulator::new(rt~)
  let producer = Memo::new(rt, () => {
    a.push(s.get())
    1
  })
  let consumer = Memo::new(rt, () => producer.accumulated(a)[0])
  inspect(rt.read(consumer), content="1")
  s.set(42)
  // producer's accumulated push-set changed; consumer must recompute and
  // return the new value.
  inspect(rt.read(consumer), content="42")
}

///|
test "memo dispose clears entries from all accumulators" {
  let rt = Runtime::new()
  let a : Accumulator[Int] = Accumulator::new(rt~)
  let b : Accumulator[Int] = Accumulator::new(rt~)
  let scope = Scope::new(rt)
  let producer : Memo[Int] = scope.memo(() => {
    a.push(1)
    b.push(2)
    0
  })
  let _ = rt.read(producer)
  inspect(a.per_memo.contains(producer.id()), content="true")
  inspect(b.per_memo.contains(producer.id()), content="true")
  scope.dispose()
  inspect(a.per_memo.contains(producer.id()), content="false")
  inspect(b.per_memo.contains(producer.id()), content="false")
  inspect(rt.accumulator_contributions.contains(producer.id()), content="false")
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
