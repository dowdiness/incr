///|
/// One Store owns its clocks and identity; it owns no Region registry.
pub struct Store {
  priv id : StoreId
  priv revision_clock : Ref[Int]
  priv change_epoch : Ref[Int]
  priv revision_changed_at : Ref[ChangeEpoch]
  priv next_sequence : Ref[Int]
}

///|
/// Creates a Store at Revision zero.
pub fn Store::Store() -> Store {
  {
    id: fresh_store_id(),
    revision_clock: Ref(0),
    change_epoch: Ref(0),
    revision_changed_at: Ref(0),
    next_sequence: Ref(1),
  }
}

///|
/// Returns this Store's committed Revision snapshot.
pub fn Store::revision(self : Store) -> Revision {
  { value: self.revision_clock.val }
}

///|
/// Reads a View as one root snapshot.
pub fn[V] Store::read(self : Store, view : View[V]) -> Result[V, ReadError] {
  if view.owner != self.id {
    Err(ReadError::CrossStore(view_store=view.owner, reader_store=self.id))
  } else {
    match phase_root_error(self.id) {
      Some(error) => Err(error)
      None => {
        let session : EvalSession = {
          owner: self.id,
          revision: self.revision(),
          change_epoch: self.change_epoch.val,
          revision_changed_at: self.revision_changed_at,
          active: Ref(true),
        }
        let context = QueryContext::root(session)
        execution_phase.val = Evaluating(self.id)
        let result = (view.recipe)(context)
        context.session.active.val = false
        context.expire()
        execution_phase.val = Idle
        result
      }
    }
  }
}

///|
fn Store::allocate(self : Store) -> Int {
  let sequence = self.next_sequence.val
  self.next_sequence.val = sequence + 1
  sequence
}
