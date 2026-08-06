///|
priv struct RevisionStamped {
  value : Int
  changed_at : @incr.Revision
  fingerprint : Int
  callback : () -> Unit
}

///|
impl @incr.HasChangedAt for RevisionStamped with fn changed_at(self) -> @incr.Revision {
  self.changed_at
}

///|
impl @incr.BackdateEq for RevisionStamped with fn backdate_equal(self, other) -> Bool {
  self.changed_at == other.changed_at && self.fingerprint == other.fingerprint
}

///|
priv struct NonEqValue {
  value : Int
  callback : () -> Unit
}

///|
fn[T] read_view(view : @surface.View[T]) -> T {
  view() catch {
    _ => abort("unexpected prototype read failure")
  }
}

///|
fn main {
  println("PROTOTYPE V12.3 backdate surface")
  let store = @surface.Store()
  let eq_view = store.derived(() => 42, label="eq")
  println("eq.value=\{read_view(eq_view)}")
  let revision = @incr.Revision::initial()
  let stamped_view = store.derived_with_backdate(
    () => RevisionStamped::{
      value: 7,
      changed_at: revision,
      fingerprint: 11,
      callback: () => (),
    },
    label="revision-stamped",
  )
  let stamped = read_view(stamped_view)
  (stamped.callback)()
  println(
    "backdate.value=\{stamped.value},revision=initial,fingerprint=\{stamped.fingerprint}",
  )
  let same_identity = RevisionStamped::{
    value: 99,
    changed_at: revision,
    fingerprint: 11,
    callback: () => (),
  }
  let different_fingerprint = RevisionStamped::{
    value: 7,
    changed_at: revision,
    fingerprint: 12,
    callback: () => (),
  }
  println(
    "backdate.same_identity=\{@incr.BackdateEq::backdate_equal(stamped, same_identity)}",
  )
  println(
    "backdate.different_fingerprint=\{@incr.BackdateEq::backdate_equal(stamped, different_fingerprint)}",
  )
  let no_backdate_view = store.derived_no_backdate(
    () => NonEqValue::{ value: 5, callback: () => () },
    label="no-backdate",
  )
  let non_eq = read_view(no_backdate_view)
  (non_eq.callback)()
  println("no_backdate.non_eq.value=\{non_eq.value}")
  println("positive_probes=PASS")
}
