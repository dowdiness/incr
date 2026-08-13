///|
/// A transaction-local erased application command.
priv struct StagedWrite {
  apply : () -> Unit
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
/// The result of one committed transaction.
pub(all) struct TransactionOutcome {
  revision : Revision
  staged_count : Int
  applied_count : Int
  advanced : Bool
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
  match (self.session.active.val, execution_phase.val) {
    (false, _) => Err(TransactionError::ExpiredTransaction)
    (true, Transacting(owner)) if owner == self.session.owner =>
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
          apply: () => source.core.value.val = Some(value),
        })
        Ok(())
      }
    _ => Err(TransactionError::ExpiredTransaction)
  }
}

///|
/// Returns whether an ignored failed set has poisoned this transaction.
pub fn Transaction::is_poisoned(self : Transaction) -> Bool {
  self.session.poisoned.val is Some(_)
}

///|
/// Returns the number of final staged Sources.
pub fn Transaction::staged_count(self : Transaction) -> Int {
  self.session.writes.length()
}

///|
/// Publishes all final staged writes atomically or rolls them back.
pub fn Store::transaction(
  self : Store,
  callback : (Transaction) -> Result[Unit, TransactionError],
) -> Result[TransactionOutcome, TransactionError] {
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
      let result : Result[TransactionOutcome, TransactionError] = match
        callback_result {
        Err(error) => Err(error)
        Ok(_) =>
          match session.poisoned.val {
            Some(error) => Err(error)
            None => {
              let staged_count = session.writes.length()
              session.writes.each((_, write) => (write.apply)())
              let advanced = staged_count > 0
              if advanced {
                self.revision_clock.val = self.revision_clock.val + 1
                self.change_epoch.val = self.change_epoch.val + 1
              }
              Ok({
                revision: self.revision(),
                staged_count,
                applied_count: staged_count,
                advanced,
              })
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
