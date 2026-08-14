///|
priv enum ExecutionPhase {
  Idle
  Evaluating(StoreId)
  Transacting(StoreId)
}

///|
/// The alpha kernel intentionally serializes all Store activity.
let execution_phase : Ref[ExecutionPhase] = Ref(Idle)

///|
let next_store_id : Ref[Int] = Ref(1)

///|
fn fresh_store_id() -> StoreId {
  let value = next_store_id.val
  next_store_id.val = value + 1
  { value, }
}

///|
fn phase_region_error() -> RegionError? {
  match execution_phase.val {
    Idle => None
    Evaluating(active_store) =>
      Some(RegionError::MutationDuringEvaluation(active_store~))
    Transacting(active_store) =>
      Some(RegionError::MutationDuringTransaction(active_store~))
  }
}

///|
fn phase_root_error(requested_store : StoreId) -> ReadError? {
  match execution_phase.val {
    Idle => None
    Evaluating(active_store) =>
      Some(ReadError::ReentrantRootRead(active_store~, requested_store~))
    Transacting(active_store) =>
      Some(ReadError::ReadDuringTransaction(active_store~, requested_store~))
  }
}

///|
fn phase_transaction_error() -> TransactionError? {
  match execution_phase.val {
    Idle => None
    Evaluating(active_store) =>
      Some(TransactionError::TransactionDuringEvaluation(active_store~))
    Transacting(active_store) =>
      Some(TransactionError::NestedTransaction(active_store~))
  }
}
