///|
/// Structural failures while evaluating one View recipe.
pub(all) enum ReadError {
  CrossStore(view_store~ : StoreId, reader_store~ : StoreId)
  ClosedRegion(generation~ : RegionGeneration)
  ExpiredEvalContext(eval_id~ : EvalId)
  ReentrantRootRead(active_store~ : StoreId, requested_store~ : StoreId)
  ReadDuringTransaction(active_store~ : StoreId, requested_store~ : StoreId)
} derive(Eq, Debug)

///|
/// Region lifecycle/definition failures.
pub(all) enum RegionError {
  ClosedRegion(generation~ : RegionGeneration)
  MutationDuringEvaluation(active_store~ : StoreId)
  MutationDuringTransaction(active_store~ : StoreId)
}
  derive(Eq, Debug)

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
}
  derive(Eq, Debug)

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
  compute_count : Int
  memo_count : Int
  cache_hits : Int
  green_verifications : Int
  failed_recomputes : Int
}

///| Immutable state of one typed memo entry for executable evidence.
pub(all) struct MemoDebug {
  memo_id : MemoId
  trace_length : Int
  verified_at : ChangeEpoch
  changed_at : ChangeEpoch
}

///|
/// Result of checking an old dependency. It never carries a dependency error;
/// a failed or closed upstream is simply a reason to recompute the owner.
priv enum Verification {
  ProvenUnchanged(ChangeEpoch)
  RecomputeRequired
}
