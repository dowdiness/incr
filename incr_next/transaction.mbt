///|
/// A transaction-local erased application command.
priv struct StagedWrite {
  apply : (ChangeEpoch) -> Unit
}

///|
priv struct TransactionSession {
  owner : StoreId
  active : Ref[Bool]
  poisoned : Ref[TransactionError?]
  writes : Map[SourceId, StagedWrite]
}

///|
/// A write capability valid only during its Store.transaction callback.
pub struct Transaction {
  priv session : TransactionSession
}

///|
fn Transaction::poison(
  self : Transaction,
  error : TransactionError,
) -> Result[Unit, TransactionError] {
  if self.session.poisoned.val is None {
    self.session.poisoned.val = Some(error)
  }
  Err(error)
}

///|
/// Stages a typed Source write after provenance and lifetime validation.
pub fn[T] Transaction::set(
  self : Transaction,
  source : Source[T],
  value : T,
) -> Result[Unit, TransactionError] {
  match (self.session.active.val, self.session.poisoned.val) {
    (false, _) => Err(TransactionError::ExpiredTransaction)
    (true, Some(error)) => Err(error)
    (true, None) =>
      match execution_phase.val {
        Transacting(owner) if owner == self.session.owner =>
          if source.core.owner != self.session.owner {
            self.poison(
              TransactionError::CrossStore(
                source_store=source.core.owner,
                transaction_store=self.session.owner,
              ),
            )
          } else if !source.core.epoch.accepts(source.core.generation) {
            self.poison(
              TransactionError::ClosedRegion(generation=source.core.generation),
            )
          } else {
            self.session.writes.set(source.core.source_id, {
              apply: next_epoch => {
                source.core.value.val = Some(value)
                source.core.changed_at.val = next_epoch
              },
            })
            Ok(())
          }
        _ => Err(TransactionError::ExpiredTransaction)
      }
  }
}

///|
/// Publishes all final staged writes atomically or rolls them back.
///
/// A successful transaction returns the Store's resulting committed Revision.
pub fn Store::transaction(
  self : Store,
  callback : (Transaction) -> Result[Unit, TransactionError],
) -> Result[Revision, TransactionError] {
  match phase_transaction_error() {
    Some(error) => Err(error)
    None => {
      let session : TransactionSession = {
        owner: self.id,
        active: Ref(true),
        poisoned: Ref(None),
        writes: Map([]),
      }
      let transaction : Transaction = { session, }
      execution_phase.val = Transacting(self.id)
      let callback_result = callback(transaction)
      let result : Result[Revision, TransactionError] = match
        session.poisoned.val {
        Some(error) => Err(error)
        None =>
          match callback_result {
            Err(error) => Err(error)
            Ok(_) => {
              let staged = session.writes.length() > 0
              if staged {
                let next_epoch = self.change_epoch.val + 1
                session.writes.each((_, write) => (write.apply)(next_epoch))
                self.revision_clock.val = self.revision_clock.val + 1
                self.change_epoch.val = next_epoch
                self.revision_changed_at.val = next_epoch
              }
              Ok(self.revision())
            }
          }
      }
      session.writes.clear()
      session.active.val = false
      execution_phase.val = Idle
      result
    }
  }
}
