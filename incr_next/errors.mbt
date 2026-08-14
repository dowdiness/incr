///|
/// Structural failures reported by Store and QueryContext reads.
pub(all) enum ReadError {
  CrossStore(view_store~ : StoreId, reader_store~ : StoreId)
  ClosedRegion(generation~ : RegionGeneration)
  ExpiredQueryContext
  ReentrantRootRead(active_store~ : StoreId, requested_store~ : StoreId)
  ReadDuringTransaction(active_store~ : StoreId, requested_store~ : StoreId)
} derive(Eq, Debug)

///|
/// Structural failures while creating or closing a Region.
pub(all) enum RegionError {
  ClosedRegion(generation~ : RegionGeneration)
  MutationDuringEvaluation(active_store~ : StoreId)
  MutationDuringTransaction(active_store~ : StoreId)
} derive(Eq, Debug)

///|
/// Structural failures while staging a transaction.
pub(all) enum TransactionError {
  CrossStore(source_store~ : StoreId, transaction_store~ : StoreId)
  ClosedRegion(generation~ : RegionGeneration)
  ExpiredTransaction
  TransactionDuringEvaluation(active_store~ : StoreId)
  NestedTransaction(active_store~ : StoreId)
  CallbackRejected
} derive(Eq, Debug)
