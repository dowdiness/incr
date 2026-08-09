///|
/// Copied QueryId path; it never retains keys, frames, or QueryCore values.
pub(all) struct CycleWitness {
  path : Array[QueryId]
} derive(Eq, Debug)

///|
/// Structural failures while evaluating one View recipe.
pub(all) enum ReadError {
  CrossStore(view_store~ : StoreId, reader_store~ : StoreId)
  ClosedRegion(generation~ : RegionGeneration)
  ExpiredEvalContext(eval_id~ : EvalId)
  ReentrantRootRead(active_store~ : StoreId, requested_store~ : StoreId)
  ReadDuringTransaction(active_store~ : StoreId, requested_store~ : StoreId)
  Cycle(CycleWitness)
} derive(Eq, Debug)

///|
/// Region lifecycle/definition failures.
pub(all) enum RegionError {
  ClosedRegion(generation~ : RegionGeneration)
  MutationDuringEvaluation(active_store~ : StoreId)
  MutationDuringTransaction(active_store~ : StoreId)
} derive(Eq, Debug)

///|
/// Explicit memo eviction phase and lifetime failures.
pub(all) enum EvictionError {
  ClosedRegion(generation~ : RegionGeneration)
  EvictionDuringEvaluation(active_store~ : StoreId, requested_store~ : StoreId)
  EvictionDuringTransaction(active_store~ : StoreId, requested_store~ : StoreId)
} derive(Eq, Debug)

///|
/// Transaction validation and lifecycle failures.
pub(all) enum TransactionError {
  CrossStore(source_store~ : StoreId, transaction_store~ : StoreId)
  ClosedRegion(generation~ : RegionGeneration)
  ExpiredTransaction(transaction_id~ : TransactionId)
  TransactionDuringEvaluation(
    active_store~ : StoreId,
    requested_store~ : StoreId
  )
  NestedTransaction(active_store~ : StoreId, requested_store~ : StoreId)
  CallbackRejected
} derive(Eq, Debug)

///|
/// Successful transaction summary.
pub(all) struct TransactionOutcome {
  revision : Revision
  change_epoch : ChangeEpoch
  staged_count : Int
  applied_count : Int
  advanced : Bool
}

///|
/// Immutable Store counter snapshot.
pub(all) struct StoreDebug {
  root_read_attempts : Int
  root_read_rejections : Int
  transaction_attempts : Int
  transaction_commits : Int
  transaction_rollbacks : Int
  last_finished_active_depth : Int
  mount_count : Int
  active_edge_count : Int
}

///|
/// Immutable Source state snapshot.
pub(all) struct SourceDebug {
  source_id : SourceId
  generation : RegionGeneration
  committed : Bool
  read_count : Int
  verification_count : Int
  changed_at : ChangeEpoch
}

///|
/// Immutable Query state snapshot.
pub(all) struct QueryDebug {
  query_id : QueryId
  generation : RegionGeneration
  compute_available : Bool
  cutoff_available : Bool
  compute_count : Int
  cutoff_calls : Int
  eviction_attempts : Int
  evictions : Int
  eviction_noops : Int
  eviction_rejections : Int
  memo_count : Int
  cache_hits : Int
  green_verifications : Int
  failed_recomputes : Int
  active_count : Int
}

///|
/// Immutable state of one typed memo entry for executable evidence.
pub(all) struct MemoDebug {
  memo_id : MemoId
  trace_length : Int
  verified_at : ChangeEpoch
  changed_at : ChangeEpoch
}

///|
/// The typed error channel for a disposed mount.
pub(all) enum MountError {
  CrossStore(view_store~ : StoreId, mount_store~ : StoreId)
  ClosedRegion(generation~ : RegionGeneration)
  MountDuringEvaluation(active_store~ : StoreId, requested_store~ : StoreId)
  MountDuringTransaction(active_store~ : StoreId, requested_store~ : StoreId)
  DisposedMount(MountId)
} derive(Eq, Debug)

///|
/// Immutable evidence for one mounted root.
pub(all) struct MountDebug {
  mount_id : MountId
  disposed : Bool
  runner_registered : Bool
  evaluation_count : Int
  wake_count : Int
  success_count : Int
  failure_count : Int
  successful_footprint_length : Int
  failed_attempt_footprint_length : Int
  active_token_count : Int
}

///|
/// Result of checking an old dependency. It never carries a dependency error;
/// a failed or closed upstream is simply a reason to recompute the owner.
priv enum Verification {
  ProvenUnchanged(changed_at~ : ChangeEpoch, footprint~ : Array[WakeToken])
  RecomputeRequired
}
