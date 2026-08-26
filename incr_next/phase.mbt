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
    Evaluating(_) => Some(region_mutation_during_evaluation())
    Transacting(_) => Some(region_mutation_during_transaction())
  }
}

///|
fn phase_root_error(_requested_store : StoreId) -> ReadError? {
  match execution_phase.val {
    Idle => None
    Evaluating(_) => Some(read_reentrant_root_get())
    Transacting(_) => Some(read_get_during_transaction())
  }
}

///|
fn phase_transaction_error() -> TransactionError? {
  match execution_phase.val {
    Idle => None
    Evaluating(_) => Some(transaction_during_evaluation())
    Transacting(_) => Some(nested_transaction())
  }
}
