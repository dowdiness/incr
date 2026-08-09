///|
priv struct StagedWrite {
  apply : (ChangeEpoch) -> Unit
}

///|
priv struct TransactionSession {
  owner : StoreCore
  transaction_id : TransactionId
  active : Ref[Bool]
  poisoned : Ref[TransactionError?]
  writes : Map[SourceId, StagedWrite]
}

///|
pub(all) struct Transaction {
  priv session : TransactionSession
}

///|
fn[T] staged_source_write(core : SourceCore[T], value : T) -> StagedWrite {
  { apply: epoch => core.commit(value, epoch) }
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
pub fn Transaction::staged_count(self : Transaction) -> Int {
  self.session.writes.length()
}

///|
pub fn Transaction::is_poisoned(self : Transaction) -> Bool {
  self.session.poisoned.val is Some(_)
}

///|
pub fn Transaction::id(self : Transaction) -> TransactionId {
  self.session.transaction_id
}

///|
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
          sequence: self.core.allocate_session(),
        },
        active: Ref(true),
        poisoned: Ref(None),
        writes: Map([]),
      }
      let transaction = Transaction::{ session, }
      let touched : Array[WakeToken] = []
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
              if staged_count == 0 {
                self.core.counters.transaction_commits = self.core.counters.transaction_commits +
                  1
                Ok(TransactionOutcome::{
                  revision: self.core.current_revision(),
                  change_epoch: self.core.current_change_epoch(),
                  staged_count,
                  applied_count: 0,
                  advanced: false,
                })
              } else {
                let target_epoch = self.core.next_change_epoch()
                session.writes.each((source_id, write) => {
                  touched.push(WakeToken::Source(source_id))
                  (write.apply)(target_epoch)
                })
                touched.push(WakeToken::RevisionClock(self.core.id))
                let revision = self.core.commit_revision(target_epoch)
                self.core.counters.transaction_commits = self.core.counters.transaction_commits +
                  1
                Ok(TransactionOutcome::{
                  revision,
                  change_epoch: target_epoch,
                  staged_count,
                  applied_count: staged_count,
                  advanced: true,
                })
              }
            }
          }
      }
      session.writes.clear()
      session.active.val = false
      execution_mode.val = Idle
      match result {
        Ok(outcome) if outcome.advanced =>
          self.core.wake_selected_mounts(touched)
        _ => ()
      }
      result
    }
  }
}
