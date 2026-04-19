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
test "Scope::accumulator disposed with scope" {
  let rt = Runtime::new()
  let scope = Scope::new(rt)
  let a : Accumulator[Int] = scope.accumulator(label="s")
  inspect(a.is_disposed(), content="false")
  scope.dispose()
  inspect(a.is_disposed(), content="true")
}

///|
test "edge: ActiveQuery.accumulator_reads discarded on recompute failure" {
  let rt = Runtime::new()
  let should_fail = Signal::new(rt, false)
  let acc_a : Accumulator[Int] = Accumulator::new(rt~)
  let producer = Memo::new(rt, () => {
    acc_a.push(1)
    0
  })
  let _ = rt.ensure_computed_untracked(producer.id())
  let consumer = Memo::new(rt, () => {
    let _ = producer.accumulated(acc_a)
    if should_fail.get() {
      fail("abort")
    }
    1
  })
  let _ = rt.ensure_computed_untracked(consumer.id())
  let consumer_data = rt.get_memo_data(consumer.id())
  inspect(consumer_data.accumulator_reads.is_empty(), content="false")
  // Trigger failing recompute (via ensure_computed_untracked so the Failure
  // propagates to our catch — rt.read would convert raise → abort)
  should_fail.set(true)
  let _ = try {
    let _ = rt.ensure_computed_untracked(consumer.id())
    ()
  } catch {
    _ => ()
  }
  // consumer's accumulator_reads must NOT contain stale entries from the
  // failed run — prior successful run's entry should remain (single entry).
  let data_after = rt.get_memo_data(consumer.id())
  inspect(data_after.accumulator_reads.length() <= 1, content="true")
}

///|
test "edge: new-run-only slot cleared on ON_ABORT" {
  let rt = Runtime::new()
  let use_b = Signal::new(rt, false)
  let acc_a : Accumulator[Int] = Accumulator::new(rt~)
  let acc_b : Accumulator[Int] = Accumulator::new(rt~)
  // First run: pushes only to A
  let m = Memo::new(rt, () => {
    acc_a.push(1)
    if use_b.get() {
      acc_b.push(99)
      fail("boom after pushing to b")
    }
    0
  })
  let _ = rt.ensure_computed_untracked(m.id())
  inspect(acc_b.per_memo.contains(m.id()), content="false")
  // Trigger failing recompute that pushes to B before failing
  use_b.set(true)
  let _ = try {
    let _ = rt.ensure_computed_untracked(m.id())
    ()
  } catch {
    _ => ()
  }
  // acc_b was NOT in prev_contributions; ON_ABORT must clear its per_memo
  // entry for m, otherwise a stale push_set survives.
  inspect(acc_b.per_memo.contains(m.id()), content="false")
  // acc_a was in prev; its buffer should be restored.
  inspect(acc_a.per_memo.get(m.id()).unwrap().length(), content="1")
}

///|
test "edge: first-push-to-fresh-memo correctly bumps push_revised_at" {
  let rt = Runtime::new()
  let trigger = Signal::new(rt, false)
  let acc : Accumulator[Int] = Accumulator::new(rt~)
  let m = Memo::new(rt, () => {
    if trigger.get() {
      acc.push(100)
    }
    0
  })
  let _ = rt.ensure_computed_untracked(m.id())
  // No push yet → no push_revised_at entry
  inspect(acc.push_revised_at.contains(m.id()), content="false")
  trigger.set(true)
  let _ = rt.ensure_computed_untracked(m.id())
  // Now first push happened; push_revised_at must bump (empty != [100])
  inspect(acc.push_revised_at.contains(m.id()), content="true")
}

///|
test "panic: Memo::accumulated_peek aborts on cross-runtime Accumulator" {
  let rt1 = Runtime::new()
  let rt2 = Runtime::new()
  let acc1 : Accumulator[Int] = Accumulator::new(rt=rt1)
  let m2 = Memo::new(rt2, () => 1)
  // Would silently index rt2.accumulator_slots with acc1.slot_id (from rt1)
  // without the cross-runtime guard on acc.slot_id.runtime_id.
  let _ = m2.accumulated_peek(acc1)
}

///|
/// Regression: compute that raises Failure during pull_verify's frame
/// finalization must clear ancestor in_progress flags, otherwise subsequent
/// reads report false CycleError.
test "verify: raise-path from compute does not leak in_progress on ancestors" {
  let rt = Runtime::new()
  let should_fail = Signal::new(rt, false)
  let inner : Memo[Int] = Memo::new(rt, () => {
    if should_fail.get() {
      fail("boom")
    } else {
      1
    }
  })
  let outer : Memo[Int] = Memo::new(rt, () => inner.get() + 1)
  // Prime dependency graph: outer depends on inner, both verified.
  let _ = rt.ensure_computed_untracked(outer.id())
  // Trigger failing recompute path — inner raises when verified through outer.
  should_fail.set(true)
  let caught = try {
    let _ = rt.ensure_computed_untracked(outer.id())
    false
  } catch {
    _ => true
  }
  inspect(caught, content="true")
  // If the raise-path forgot to clear outer.in_progress, the next verify
  // treats outer as mid-computation and returns a CycleError (which
  // rt.read converts to abort). The test then panics on rt.read.
  should_fail.set(false)
  inspect(rt.read(outer), content="2")
}

///|
/// Regression: non-root memo frames must evaluate their own accumulator_reads
/// during pull_verify's finalize step. Without this, a middle memo whose
/// output derives from accumulated(...) is marked verified without
/// recomputation when its producer's push-set changed, and parents reading
/// via ordinary get() see stale values.
test "verify: non-root frame checks accumulator_reads" {
  let rt = Runtime::new()
  let s = Signal::new(rt, 1)
  let a : Accumulator[Int] = Accumulator::new(rt~)
  let producer = Memo::new(rt, () => {
    a.push(s.get())
    1
  })
  let middle = Memo::new(rt, () => producer.accumulated(a)[0])
  let top = Memo::new(rt, () => middle.get() * 10)
  inspect(rt.read(top), content="10")
  s.set(5)
  // Without the non-root synthetic check, middle skips recompute even
  // though producer's push-set changed, and top returns stale 10.
  inspect(rt.read(top), content="50")
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

///|
/// Regression: ON_ABORT cleanup for new-run-only slots (slots touched in
/// the aborted run but not in prev_contributions) must not roll back
/// push_revised_at for the producer. Prior code called dispose_memo,
/// which wiped push_revised_at, causing consumers with a pre-existing
/// stored revision to miss invalidation and return stale cached values
/// after abort + retry.
test "verify: aborted new-slot push preserves prior push_revised_at" {
  let rt = Runtime::new()
  let sig = Signal::new(rt, 1)
  let acc : Accumulator[Int] = Accumulator::new(rt~)
  // Producer behavior:
  //   sig=1  → push [1]
  //   sig=0  → push nothing
  //   sig=99 → push [99], then fail
  let producer = Memo::new_no_backdate(rt, () => {
    let v = sig.get()
    if v > 0 && v != 99 {
      acc.push(v)
    }
    if v == 99 {
      acc.push(99)
      fail("producer aborts on sig=99")
    }
    0
  })
  let consumer = Memo::new_no_backdate(rt, () => {
    producer.accumulated(acc).length()
  })
  // R0: sig=1 → producer pushes [1]; consumer reads len=1; stored=R0.
  inspect(rt.read(consumer), content="1")
  // R1: sig=0 → producer recomputes directly (pushes nothing;
  // push_revised_at bumps, per_memo entry is removed). Consumer does NOT
  // read here, so its stored revision stays at R0.
  sig.set(0)
  match rt.ensure_computed_untracked(producer.id()) {
    Ok(_) => ()
    Err(e) => fail("R1 unexpected cycle: " + e.format_path())
  }
  // R2: sig=99 → producer aborts while pushing to slot that is NOT in
  // prev_contributions (cleared during R1's empty finalize). Prior code
  // called dispose_memo, which wiped push_revised_at.
  sig.set(99)
  let r2_aborted = try {
    let _ = rt.ensure_computed_untracked(producer.id())
    false
  } catch {
    _ => true
  }
  inspect(r2_aborted, content="true")
  // R3: sig=0 (same as R1). Producer recomputes without bumping
  // push_revised_at (prev=[], current=[], same). Consumer must see the
  // updated state via the preserved R1 marker — not a stale 1 from R0.
  sig.set(0)
  inspect(rt.read(consumer), content="0")
}
