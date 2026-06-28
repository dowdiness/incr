// Tests for HasChangedAt and BackdateEq traits.
// BackdateEq.backdate_equal defaults to comparing changed_at revisions.

///|
using @incr_types {trait HasChangedAt, trait BackdateEq}

///|
priv struct Stamped {
  value : Int
  changed_at : Revision
}

///|
impl HasChangedAt for Stamped with fn changed_at(self) -> Revision {
  self.changed_at
}

///|
impl BackdateEq for Stamped

///|
test "BackdateEq default: same changed_at → backdate_equal returns true" {
  let r = Revision::initial()
  let a = Stamped::{ value: 1, changed_at: r }
  let b = Stamped::{ value: 2, changed_at: r }
  // Values differ (1 vs 2) but revision is the same — BackdateEq only compares revisions.
  inspect(a.value == b.value, content="false")
  inspect(a.backdate_equal(b), content="true")
}

///|
test "BackdateEq default: different changed_at → backdate_equal returns false" {
  let r0 = Revision::initial()
  let r1 = r0.next()
  let a = Stamped::{ value: 1, changed_at: r0 }
  let b = Stamped::{ value: 1, changed_at: r1 }
  inspect(a.backdate_equal(b), content="false")
}

///|
test "BackdateEq default: same value but different changed_at → backdate_equal returns false" {
  // Default impl compares revisions, not values — so different revision → false even if value equal
  let r0 = Revision::initial()
  let r1 = r0.next()
  let a = Stamped::{ value: 42, changed_at: r0 }
  let b = Stamped::{ value: 42, changed_at: r1 }
  inspect(a.backdate_equal(b), content="false")
}

///|
test "with_backdate: backdates when backdate_equal returns true (same changed_at)" {
  // Stamped returns same changed_at when value is "unchanged" — downstream skips
  let rt = Runtime::Runtime()
  let rev_ref : Ref[Revision] = { val: Revision::initial() }
  let m_count : Ref[Int] = { val: 0 }
  let sig = Signal::Signal(rt, 0)
  let m = Derived::with_backdate(
    rt,
    () => {
      let _ = sig.get()
      m_count.val = m_count.val + 1
      // Don't advance rev_ref — value is "unchanged"
      Stamped::{ value: 42, changed_at: rev_ref.val }
    },
    (a, b) => a.backdate_equal(b),
  )
  let down_count : Ref[Int] = { val: 0 }
  let _down = Derived(rt, () => {
    let _ = m.get_or_abort()
    down_count.val = down_count.val + 1
    0
  })
  // First compute
  let _ = _down.read_or_abort()
  inspect(m_count.val, content="1")
  inspect(down_count.val, content="1")
  // Trigger recompute of m (sig changed) but rev_ref stays same → backdate fires
  sig.set(1)
  let _ = _down.read_or_abort()
  inspect(m_count.val, content="2") // m recomputed
  inspect(down_count.val, content="1") // downstream did NOT recompute (backdated)
}

///|
test "with_backdate: propagates when backdate_equal returns false (advanced changed_at)" {
  let rt = Runtime::Runtime()
  let rev_ref : Ref[Revision] = { val: Revision::initial() }
  let m_count : Ref[Int] = { val: 0 }
  let sig = Signal::Signal(rt, 0)
  let m = Derived::with_backdate(
    rt,
    () => {
      let v = sig.get()
      m_count.val = m_count.val + 1
      // Advance rev_ref — value is "changed"
      rev_ref.val = rev_ref.val.next()
      Stamped::{ value: v, changed_at: rev_ref.val }
    },
    (a, b) => a.backdate_equal(b),
  )
  let down_count : Ref[Int] = { val: 0 }
  let _down = Derived(rt, () => {
    let _ = m.get_or_abort()
    down_count.val = down_count.val + 1
    0
  })
  let _ = _down.read_or_abort()
  inspect(m_count.val, content="1")
  inspect(down_count.val, content="1")
  sig.set(1)
  let _ = _down.read_or_abort()
  inspect(m_count.val, content="2") // m recomputed
  inspect(down_count.val, content="2") // downstream also recomputed (no backdate)
}

///|
test "derived_no_backdate: always propagates even when value is identical" {
  let rt = Runtime::Runtime()
  let m_count : Ref[Int] = { val: 0 }
  let sig = Signal::Signal(rt, 0)
  let m = Derived::derived_no_backdate(rt, () => {
    let _ = sig.get()
    m_count.val = m_count.val + 1 // always returns same value
    42
  })
  let down_count : Ref[Int] = { val: 0 }
  let _down = Derived(rt, () => {
    let _ = m.get_or_abort()
    down_count.val = down_count.val + 1
    0
  })
  let _ = _down.read_or_abort()
  inspect(m_count.val, content="1")
  inspect(down_count.val, content="1")
  sig.set(1)
  let _ = _down.read_or_abort()
  inspect(m_count.val, content="2") // m recomputed
  inspect(down_count.val, content="2") // downstream ALSO recomputed (never backdates)
}

///|
// A type with no Eq instance — verifies new_no_backdate is usable without Eq.
priv struct NoEq {
  data : Array[Int]
}

///|
test "derived_no_backdate: usable with non-Eq output type" {
  let rt = Runtime::Runtime()
  let sig = Signal::Signal(rt, 0)
  let m = Derived::derived_no_backdate(rt, () => NoEq::{ data: [sig.get()] })
  // read() must work without T : Eq
  inspect(m.read_or_abort().data[0], content="0")
  sig.set(42)
  inspect(m.read_or_abort().data[0], content="42")
}

///|
test "compatibility: Derived::with_backdate backdates via BackdateEq (unchanged changed_at)" {
  // Created through Derived::with_backdate, not Memo::new_memo.
  let rt = Runtime::Runtime()
  let rev_ref : Ref[Revision] = { val: Revision::initial() }
  let sig = Signal::Signal(rt, 0)
  let m = Derived::with_backdate(
    rt,
    () => {
      let _ = sig.get()
      Stamped::{ value: 42, changed_at: rev_ref.val }
    },
    (a, b) => a.backdate_equal(b),
  )
  let down_count = Ref(0)
  let down = Derived(rt, () => {
    let _ = m.get_or_abort()
    down_count.val = down_count.val + 1
    0
  })
  let _ = down.read_or_abort()
  inspect(down_count.val, content="1")
  // sig changes but rev_ref stays same → BackdateEq says unchanged → backdate fires
  sig.set(1)
  let _ = down.read_or_abort()
  inspect(down_count.val, content="1") // downstream NOT recomputed (backdated)
}
