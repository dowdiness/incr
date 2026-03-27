// Tests for HasChangedAt and BackdateEq traits.
// BackdateEq.backdate_equal defaults to comparing changed_at revisions.

///|
priv struct Stamped {
  value : Int
  changed_at : @incr.Revision
}

///|
impl @incr.HasChangedAt for Stamped with changed_at(self) -> @incr.Revision {
  self.changed_at
}

///|
impl @incr.BackdateEq for Stamped

///|
test "BackdateEq default: same changed_at → backdate_equal returns true" {
  let r = @incr.Revision::initial()
  let a = Stamped::{ value: 1, changed_at: r }
  let b = Stamped::{ value: 2, changed_at: r }
  // Values differ (1 vs 2) but revision is the same — BackdateEq only compares revisions.
  inspect(a.value == b.value, content="false")
  inspect(a.backdate_equal(b), content="true")
}

///|
test "BackdateEq default: different changed_at → backdate_equal returns false" {
  let r0 = @incr.Revision::initial()
  let r1 = r0.next()
  let a = Stamped::{ value: 1, changed_at: r0 }
  let b = Stamped::{ value: 1, changed_at: r1 }
  inspect(a.backdate_equal(b), content="false")
}

///|
test "BackdateEq default: same value but different changed_at → backdate_equal returns false" {
  // Default impl compares revisions, not values — so different revision → false even if value equal
  let r0 = @incr.Revision::initial()
  let r1 = r0.next()
  let a = Stamped::{ value: 42, changed_at: r0 }
  let b = Stamped::{ value: 42, changed_at: r1 }
  inspect(a.backdate_equal(b), content="false")
}

///|
test "new_memo: backdates when backdate_equal returns true (same changed_at)" {
  // Stamped returns same changed_at when value is "unchanged" — downstream skips
  let rt = @incr.Runtime::new()
  let rev_ref : Ref[@incr.Revision] = { val: @incr.Revision::initial() }
  let m_count : Ref[Int] = { val: 0 }
  let sig = @incr.Signal::new(rt, 0)
  let m = @incr.Memo::new_memo(rt, fn() -> Stamped {
    let _ = sig.get()
    m_count.val = m_count.val + 1
    // Don't advance rev_ref — value is "unchanged"
    Stamped::{ value: 42, changed_at: rev_ref.val }
  })
  let down_count : Ref[Int] = { val: 0 }
  let _down = @incr.Memo::new(rt, fn() -> Int {
    let _ = m.get()
    down_count.val = down_count.val + 1
    0
  })
  // First compute
  let _ = _down.get()
  inspect(m_count.val, content="1")
  inspect(down_count.val, content="1")
  // Trigger recompute of m (sig changed) but rev_ref stays same → backdate fires
  sig.set(1)
  let _ = _down.get()
  inspect(m_count.val, content="2") // m recomputed
  inspect(down_count.val, content="1") // downstream did NOT recompute (backdated)
}

///|
test "new_memo: propagates when backdate_equal returns false (advanced changed_at)" {
  let rt = @incr.Runtime::new()
  let rev_ref : Ref[@incr.Revision] = { val: @incr.Revision::initial() }
  let m_count : Ref[Int] = { val: 0 }
  let sig = @incr.Signal::new(rt, 0)
  let m = @incr.Memo::new_memo(rt, fn() -> Stamped {
    let v = sig.get()
    m_count.val = m_count.val + 1
    // Advance rev_ref — value is "changed"
    rev_ref.val = rev_ref.val.next()
    Stamped::{ value: v, changed_at: rev_ref.val }
  })
  let down_count : Ref[Int] = { val: 0 }
  let _down = @incr.Memo::new(rt, fn() -> Int {
    let _ = m.get()
    down_count.val = down_count.val + 1
    0
  })
  let _ = _down.get()
  inspect(m_count.val, content="1")
  inspect(down_count.val, content="1")
  sig.set(1)
  let _ = _down.get()
  inspect(m_count.val, content="2") // m recomputed
  inspect(down_count.val, content="2") // downstream also recomputed (no backdate)
}

///|
test "new_no_backdate: always propagates even when value is identical" {
  let rt = @incr.Runtime::new()
  let m_count : Ref[Int] = { val: 0 }
  let sig = @incr.Signal::new(rt, 0)
  let m = @incr.Memo::new_no_backdate(rt, fn() -> Int {
    let _ = sig.get()
    m_count.val = m_count.val + 1
    42 // always returns same value
  })
  let down_count : Ref[Int] = { val: 0 }
  let _down = @incr.Memo::new(rt, fn() -> Int {
    let _ = m.get()
    down_count.val = down_count.val + 1
    0
  })
  let _ = _down.get()
  inspect(m_count.val, content="1")
  inspect(down_count.val, content="1")
  sig.set(1)
  let _ = _down.get()
  inspect(m_count.val, content="2") // m recomputed
  inspect(down_count.val, content="2") // downstream ALSO recomputed (never backdates)
}

///|
// A type with no Eq instance — verifies new_no_backdate is usable without Eq.
priv struct NoEq {
  data : Array[Int]
}

///|
test "new_no_backdate: usable with non-Eq output type" {
  let rt = @incr.Runtime::new()
  let sig = @incr.Signal::new(rt, 0)
  let m = @incr.Memo::new_no_backdate(rt, fn() -> NoEq {
    NoEq::{ data: [sig.get()] }
  })
  // get() must work without T : Eq
  inspect(m.get().data[0], content="0")
  sig.set(42)
  inspect(m.get().data[0], content="42")
}
