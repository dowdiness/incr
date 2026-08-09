///|
/// Transaction-local erased write; the closure captures SourceCore[T] + T.
priv struct StagedWrite {
  apply : () -> Unit
}

///|
/// One transaction session. It is removed after commit or rollback.
priv struct TransactionSession {
  owner : StoreCore
  transaction_id : TransactionId
  active : Ref[Bool]
  poisoned : Ref[TransactionError?]
  writes : Map[SourceId, StagedWrite]
}

///|
/// Opaque transaction capability valid only during its callback.
pub(all) struct Transaction {
  priv session : TransactionSession
}

///|
/// Erases one typed Source write into a transaction-local closure.
fn[T] staged_source_write(core : SourceCore[T], value : T) -> StagedWrite {
  { apply: () => core.commit(value) }
}

///|
/// Records the first validation failure as a sticky poison.
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
/// Stages one write after all validation; later writes to the Source replace it.
pub fn[T] Transaction::set(
  self : Transaction,
  source : Source[T],
  value : T,
) -> Result[Unit, TransactionError] {
  if !self.session.active.val ||
    !transaction_is_current(self.session.owner.id, self.session.transaction_id) {
    return Err(
      TransactionError::ExpiredTransaction(
        transaction_id=self.session.transaction_id,
      ),
    )
  }
  if source.core.owner != self.session.owner.id {
    return self.poison(
      TransactionError::CrossStore(
        source_store=source.core.owner,
        transaction_store=self.session.owner.id,
      ),
    )
  }
  if !source.core.epoch.accepts(source.core.generation) {
    return self.poison(
      TransactionError::ClosedRegion(generation=source.core.generation),
    )
  }
  self.session.writes.set(
    source.core.source_id,
    staged_source_write(source.core, value),
  )
  Ok(())
}

///|
/// Returns the current staged Source count for evidence.
pub fn Transaction::staged_count(self : Transaction) -> Int {
  self.session.writes.length()
}

///|
/// Returns whether any ignored set failure poisoned this transaction.
pub fn Transaction::is_poisoned(self : Transaction) -> Bool {
  self.session.poisoned.val is Some(_)
}

///|
/// Returns this transaction's stable identity.
pub fn Transaction::id(self : Transaction) -> TransactionId {
  self.session.transaction_id
}

///|
/// Runs a transaction callback and atomically commits or clears all writes.
pub fn Store::transaction(
  self : Store,
  callback : (Transaction) -> Result[Unit, TransactionError],
) -> Result[TransactionOutcome, TransactionError] {
  self.core.counters.transaction_attempts = self.core.counters.transaction_attempts +
    1
  match transaction_phase_error(self.core.id) {
    Some(error) => Err(error)
    None => {
      let session = TransactionSession::{
        owner: self.core,
        transaction_id: TransactionId::{
          owner: self.core.id,
          sequence: self.core.allocate(),
        },
        active: Ref(true),
        poisoned: Ref(None),
        writes: Map([]),
      }
      let transaction = Transaction::{ session, }
      execution_mode.val = ExecutionMode::Transacting(
        self.core.id,
        session.transaction_id,
      )
      let callback_result = callback(transaction)
      let result : Result[TransactionOutcome, TransactionError] = match
        callback_result {
        Err(error) => {
          self.core.counters.transaction_rollbacks = self.core.counters.transaction_rollbacks +
            1
          Err(error)
        }
        Ok(_) =>
          match session.poisoned.val {
            Some(error) => {
              self.core.counters.transaction_rollbacks = self.core.counters.transaction_rollbacks +
                1
              Err(error)
            }
            None => {
              let staged_count = session.writes.length()
              session.writes.each((_, write) => (write.apply)())
              let advanced = staged_count > 0
              let revision = if advanced {
                self.core.advance_revision()
              } else {
                self.core.current_revision()
              }
              self.core.counters.transaction_commits = self.core.counters.transaction_commits +
                1
              Ok(TransactionOutcome::{
                revision,
                staged_count,
                applied_count: staged_count,
                advanced,
              })
            }
          }
      }
      session.writes.clear()
      session.active.val = false
      execution_mode.val = ExecutionMode::Idle
      match result {
        Ok(outcome) if outcome.advanced => self.core.wake_all_mounts()
        _ => ()
      }
      result
    }
  }
}
