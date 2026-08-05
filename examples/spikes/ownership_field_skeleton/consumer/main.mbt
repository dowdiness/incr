///|
priv struct CachedPayload {
  marker : Int
  backref : Ref[@skeleton.View[CachedPayload]?]
}

///|
fn CachedPayload::CachedPayload(
  marker : Int,
  backref : Ref[@skeleton.View[CachedPayload]?],
) -> CachedPayload {
  { marker, backref }
}

///|
impl Eq for CachedPayload with fn equal(self, other) -> Bool {
  self.marker == other.marker
}

///|
fn late_bound_compute_cycle_is_constructible() -> Bool {
  let store = @skeleton.Store()
  let holder : Ref[@skeleton.View[Int]?] = Ref(None)
  let view = store.derived(() => {
    ignore(holder.val)
    1
  })
  holder.val = Some(view)
  holder.val is Some(_)
}

///|
fn cached_value_cycle_is_constructible() -> Bool {
  let store = @skeleton.Store()
  let view = store.derived(() => CachedPayload(2, Ref(None)))
  let payload = view()
  payload.backref.val = Some(view)
  payload == payload && payload.backref.val is Some(_)
}

///|
fn two_view_cycle_is_constructible() -> Bool {
  let store = @skeleton.Store()
  let a_holder : Ref[@skeleton.View[Int]?] = Ref(None)
  let b_holder : Ref[@skeleton.View[Int]?] = Ref(None)
  let a = store.derived(() => {
    ignore(b_holder.val)
    3
  })
  let b = store.derived(() => {
    ignore(a_holder.val)
    4
  })
  a_holder.val = Some(a)
  b_holder.val = Some(b)
  a_holder.val is Some(_) && b_holder.val is Some(_)
}

///|
fn main {
  let layout = @skeleton.run_layout_probe()
  let late_bound = late_bound_compute_cycle_is_constructible()
  let cached = cached_value_cycle_is_constructible()
  let two_view = two_view_cycle_is_constructible()

  println("OWNERSHIP FIELD SKELETON — THROWAWAY COMPILE PROBE")
  println("field layout:")
  println("  StoreCore passive-owner fields: 0")
  println("  StoreCore active fields: mounts, deferred, listeners")
  println("  DependencyAnchor entries: \{layout.dependency_anchors}")
  println(
    "  Input value after nominal Write.set: \{layout.input_value_after_write}",
  )
  println("active capability shape:")
  println("  mounts before close: \{layout.active_mounts_before_close}")
  println("  deferred before flush: \{layout.deferred_before_flush}")
  println("  listeners before close: \{layout.listeners_before_close}")
  println("  mounts after Stop: \{layout.mounts_after_stop}")
  println(
    "  listeners after ListenerToken.remove: \{layout.listeners_after_token_removal}",
  )
  println("  deferred after flush: \{layout.deferred_after_flush}")
  println("  active records after close: \{layout.active_records_after_close}")
  println("keyed ownership:")
  println(
    "  membership entries after retirement: \{layout.keyed_entries_after_retirement}",
  )
  println("  surviving getter value: \{layout.surviving_getter_value}")
  println("opaque ownership counterexamples:")
  println("  late-bound compute back-reference: \{late_bound}")
  println("  cached Eq payload back-reference: \{cached}")
  println("  two-View compute captures: \{two_view}")
}
