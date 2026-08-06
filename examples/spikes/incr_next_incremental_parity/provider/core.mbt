///|
priv enum ExecutionMode {
  Idle
  Evaluating(StoreId, EvalId)
  Transacting(StoreId, TransactionId)
}

///|
let execution_mode : Ref[ExecutionMode] = Ref(Idle)

///|
let next_store_identity : Ref[Int] = Ref(1)

///|
priv struct RegionEpoch {
  region_id : RegionId
  generation : Ref[Int]
  closed : Ref[Bool]
}

///|
/// StoreCore owns identity, clocks, allocators, and counters only. Definitions,
/// views, and sessions are not held in registries.
priv struct StoreCore {
  id : StoreId
  revision : Ref[Int]
  change_epoch : Ref[Int]
  revision_changed_at : Ref[ChangeEpoch]
  next_definition : Ref[Int]
  next_view : Ref[Int]
  next_session : Ref[Int]
  counters : StoreCounters
}

///|
priv struct StoreCounters {
  mut root_read_attempts : Int
  mut root_read_rejections : Int
  mut transaction_attempts : Int
  mut transaction_commits : Int
  mut transaction_rollbacks : Int
}

///|
fn new_store_core() -> StoreCore {
  let id = StoreId::{ value: next_store_identity.val }
  next_store_identity.val = next_store_identity.val + 1
  {
    id,
    revision: Ref(0),
    change_epoch: Ref(0),
    revision_changed_at: Ref(ChangeEpoch::{ value: 0 }),
    next_definition: Ref(1),
    next_view: Ref(1),
    next_session: Ref(1),
    counters: StoreCounters::{
      root_read_attempts: 0,
      root_read_rejections: 0,
      transaction_attempts: 0,
      transaction_commits: 0,
      transaction_rollbacks: 0,
    },
  }
}

///|
fn StoreCore::allocate_definition(self : StoreCore) -> Int {
  let result = self.next_definition.val
  self.next_definition.val = result + 1
  result
}

///|
fn StoreCore::allocate_view(self : StoreCore) -> Int {
  let result = self.next_view.val
  self.next_view.val = result + 1
  result
}

///|
fn StoreCore::allocate_session(self : StoreCore) -> Int {
  let result = self.next_session.val
  self.next_session.val = result + 1
  result
}

///|
fn StoreCore::current_revision(self : StoreCore) -> Revision {
  Revision::{ value: self.revision.val }
}

///|
fn StoreCore::current_change_epoch(self : StoreCore) -> ChangeEpoch {
  ChangeEpoch::{ value: self.change_epoch.val }
}

///|
fn StoreCore::next_change_epoch(self : StoreCore) -> ChangeEpoch {
  ChangeEpoch::{ value: self.change_epoch.val + 1 }
}

///|
fn StoreCore::advance_close_epoch(self : StoreCore) -> ChangeEpoch {
  self.change_epoch.val = self.change_epoch.val + 1
  self.current_change_epoch()
}

///|
fn StoreCore::commit_revision(
  self : StoreCore,
  target_epoch : ChangeEpoch,
) -> Revision {
  self.change_epoch.val = target_epoch.value
  self.revision.val = self.revision.val + 1
  self.revision_changed_at.val = target_epoch
  self.current_revision()
}

///|
fn StoreCore::new_region_epoch(self : StoreCore) -> RegionEpoch {
  let region_id = RegionId::{
    owner: self.id,
    sequence: self.allocate_definition(),
  }
  { region_id, generation: Ref(0), closed: Ref(false) }
}

///|
fn RegionEpoch::snapshot(self : RegionEpoch) -> RegionGeneration {
  { region: self.region_id, epoch: self.generation.val }
}

///|
fn RegionEpoch::accepts(
  self : RegionEpoch,
  captured : RegionGeneration,
) -> Bool {
  !self.closed.val && self.snapshot() == captured
}

///|
fn RegionEpoch::seal(self : RegionEpoch) -> Unit {
  if !self.closed.val {
    self.closed.val = true
    self.generation.val = self.generation.val + 1
  }
}

///|
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
fn transaction_phase_error(requested_store : StoreId) -> TransactionError? {
  match execution_mode.val {
    Idle => None
    Evaluating(active_store, _) =>
      Some(TransactionError::TransactionDuringEvaluation(active_store~, requested_store~))
    Transacting(active_store, _) =>
      Some(TransactionError::NestedTransaction(active_store~, requested_store~))
  }
}

///|
fn transaction_is_current(owner : StoreId, id : TransactionId) -> Bool {
  match execution_mode.val {
    Transacting(active_owner, active_id) =>
      active_owner == owner && active_id == id
    _ => false
  }
}
