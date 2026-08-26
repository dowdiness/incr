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
) -> Unit raise TransactionError {
  if self.session.poisoned.val is None {
    self.session.poisoned.val = Some(error)
  }
  raise error
}

///|
/// Stages a typed Source write after provenance and lifetime validation.
pub fn[T] Transaction::set(
  self : Transaction,
  source : Source[T],
  value : T,
) -> Unit raise TransactionError {
  match (self.session.active.val, self.session.poisoned.val) {
    (false, _) => raise transaction_expired()
    (true, Some(error)) => raise error
    (true, None) =>
      match execution_phase.val {
        Transacting(owner) if owner == self.session.owner =>
          if source.core.owner != self.session.owner {
            self.poison(transaction_cross_store())
          } else if !source.core.epoch.accepts(source.core.generation) {
            self.poison(transaction_closed_region())
          } else {
            self.session.writes.set(source.core.source_id, {
              apply: next_epoch => {
                source.core.value.val = Some(value)
                source.core.changed_at.val = next_epoch
              },
            })
          }
        _ => raise transaction_expired()
      }
  }
}

///|
/// Commits `Ok` callback data atomically or rolls back caller-owned `Err` data.
pub fn[T, E] Store::transaction(
  self : Store,
  callback : (Transaction) -> Result[T, E] raise TransactionError,
) -> Result[T, E] raise TransactionError {
  match phase_transaction_error() {
    Some(error) => raise error
    None => {
      let session : TransactionSession = {
        owner: self.id,
        active: Ref(true),
        poisoned: Ref(None),
        writes: Map([]),
      }
      let transaction : Transaction = { session, }
      execution_phase.val = Transacting(self.id)
      let callback_result : Result[Result[T, E], TransactionError] = Ok(
        callback(transaction),
      ) catch {
        error => Err(error)
      }
      let result : Result[Result[T, E], TransactionError] = match
        session.poisoned.val {
        Some(error) => Err(error)
        None =>
          match callback_result {
            Err(error) => Err(error)
            Ok(Err(error)) => Ok(Err(error))
            Ok(Ok(value)) => {
              let staged = session.writes.length() > 0
              if staged {
                let next_epoch = self.change_epoch.val + 1
                session.writes.each((_, write) => (write.apply)(next_epoch))
                self.change_epoch.val = next_epoch
              }
              Ok(Ok(value))
            }
          }
      }
      session.writes.clear()
      session.active.val = false
      execution_phase.val = Idle
      result.unwrap_or_error()
    }
  }
}
