///|
/// One Store owns its clocks and identity; it owns no Region registry.
pub struct Store {
  priv id : StoreId
  priv change_epoch : Ref[Int]
  priv next_sequence : Ref[Int]
}

///|
/// Creates an empty Store.
pub fn Store::Store() -> Store {
  { id: fresh_store_id(), change_epoch: Ref(0), next_sequence: Ref(1) }
}

///|
/// Gets a View as one root snapshot and raises structural read failure.
pub fn[V] Store::get(self : Store, view : View[V]) -> V raise ReadError {
  self.get_result(view).unwrap_or_error()
}

///|
/// Reads a View as one root snapshot.
fn[V] Store::get_result(self : Store, view : View[V]) -> Result[V, ReadError] {
  if view.owner != self.id {
    Err(read_store_cross_store())
  } else {
    match phase_root_error(self.id) {
      Some(error) => Err(error)
      None => {
        let session : EvalSession = {
          owner: self.id,
          change_epoch: self.change_epoch.val,
          active_stack: [],
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
