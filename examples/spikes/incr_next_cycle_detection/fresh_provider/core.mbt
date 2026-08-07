///|
/// One module-global single-thread execution guard shared by all Stores.
priv enum ExecutionMode {
  Idle
  Evaluating(StoreId, EvalId)
  Transacting(StoreId, TransactionId)
}

///|
/// The prototype assumes MoonBit's current single-threaded execution model.
let execution_mode : Ref[ExecutionMode] = Ref(Idle)

///|
/// Allocator for Store identities only; it is not an object registry.
let next_store_identity : Ref[Int] = Ref(1)

///|
/// Shared Region epoch. It never points back to RegionCore.
priv struct RegionEpoch {
  region_id : RegionId
  generation : Ref[Int]
  closed : Ref[Bool]
}

///|
/// Store identity, revision, allocation, and counters only.
priv struct StoreCore {
  id : StoreId
  revision : Ref[Int]
  next_sequence : Ref[Int]
  counters : StoreCounters
}

///|
/// Mutable counters hidden behind StoreDebug snapshots.
priv struct StoreCounters {
  mut root_read_attempts : Int
  mut root_read_rejections : Int
  mut transaction_attempts : Int
  mut transaction_commits : Int
  mut transaction_rollbacks : Int
  mut last_finished_active_depth : Int
}

///|
/// Creates one StoreCore without Region/Source/Query registries.
fn new_store_core() -> StoreCore {
  let id = StoreId::{ value: next_store_identity.val }
  next_store_identity.val = next_store_identity.val + 1
  {
    id,
    revision: Ref(0),
    next_sequence: Ref(1),
    counters: StoreCounters::{
      root_read_attempts: 0,
      root_read_rejections: 0,
      transaction_attempts: 0,
      transaction_commits: 0,
      transaction_rollbacks: 0,
      last_finished_active_depth: 0,
    },
  }
}

///|
/// Allocates one Store-local sequence.
fn StoreCore::allocate(self : StoreCore) -> Int {
  let sequence = self.next_sequence.val
  self.next_sequence.val = sequence + 1
  sequence
}

///|
/// Returns the current committed revision.
fn StoreCore::current_revision(self : StoreCore) -> Revision {
  Revision::{ value: self.revision.val }
}

///|
/// Advances the committed revision exactly once.
fn StoreCore::advance_revision(self : StoreCore) -> Revision {
  self.revision.val = self.revision.val + 1
  self.current_revision()
}

///|
/// Allocates one Region epoch.
fn StoreCore::new_region_epoch(self : StoreCore) -> RegionEpoch {
  let region_id = RegionId::{ owner: self.id, sequence: self.allocate() }
  { region_id, generation: Ref(0), closed: Ref(false) }
}

///|
/// Returns the current Region generation.
fn RegionEpoch::snapshot(self : RegionEpoch) -> RegionGeneration {
  { region: self.region_id, epoch: self.generation.val }
}

///|
/// Returns whether a captured generation is still open.
fn RegionEpoch::accepts(
  self : RegionEpoch,
  captured : RegionGeneration,
) -> Bool {
  !self.closed.val && self.snapshot() == captured
}

///|
/// Closes and advances one Region epoch.
fn RegionEpoch::seal(self : RegionEpoch) -> Unit {
  if !self.closed.val {
    self.closed.val = true
    self.generation.val = self.generation.val + 1
  }
}

///|
/// Returns a Region mutation error for the global phase, if any.
fn region_phase_error() -> RegionError? {
  match execution_mode.val {
    Idle => None
    Evaluating(active_store, _) =>
      Some(RegionError::MutationDuringEvaluation(active_store~))
    Transacting(active_store, _) =>
      Some(RegionError::MutationDuringTransaction(active_store~))
  }
}

///|
/// Returns a root-read phase error after metadata validation.
fn root_read_phase_error(requested_store : StoreId) -> ReadError? {
  match execution_mode.val {
    Idle => None
    Evaluating(active_store, active_eval) => {
      ignore(active_eval)
      Some(ReadError::ReentrantRootRead(active_store~, requested_store~))
    }
    Transacting(active_store, _) =>
      Some(ReadError::ReadDuringTransaction(active_store~, requested_store~))
  }
}

///|
/// Returns a transaction-start phase error.
fn transaction_phase_error(requested_store : StoreId) -> TransactionError? {
  match execution_mode.val {
    Idle => None
    Evaluating(active_store, _) =>
      Some(
        TransactionError::TransactionDuringEvaluation(
          active_store~,
          requested_store~,
        ),
      )
    Transacting(active_store, _) =>
      Some(TransactionError::NestedTransaction(active_store~, requested_store~))
  }
}

///|
/// Confirms that one captured Transaction is still the active transaction.
fn transaction_is_current(owner : StoreId, id : TransactionId) -> Bool {
  match execution_mode.val {
    Transacting(active_owner, active_id) =>
      active_owner == owner && active_id == id
    _ => false
  }
}
