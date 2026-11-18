///|
/// One Store owns its clocks and identity; it owns no Region registry.
pub struct Store {
  priv id : StoreId
  priv change_epoch : Ref[Int32]
  priv next_sequence : Ref[Int32]
  priv max_active_queries : UInt32?
}

///|
/// Creates an empty Store with an optional active Query nesting limit.
pub fn Store::Store(max_active_queries? : UInt32) -> Store {
  {
    id: fresh_store_id(),
    change_epoch: Ref(0),
    next_sequence: Ref(1),
    max_active_queries,
  }
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
          max_active_queries: self.max_active_queries,
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
fn Store::allocate(self : Store) -> Int32 {
  let sequence = self.next_sequence.val
  self.next_sequence.val = sequence + 1
  sequence
}
