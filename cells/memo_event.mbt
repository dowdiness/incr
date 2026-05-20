///|
/// Event emitted when a memo recompute starts.
pub(all) struct MemoEnteringEvent {
  cell_id : CellId
  started_revision : Revision
}

///|
/// Event emitted when a memo recompute completes successfully.
pub(all) struct MemoCompletedEvent {
  cell_id : CellId
  elapsed_ns : Int64
  started_revision : Revision
  verified_at : Revision
  changed_at : Revision
  backdated : Bool
}

///|
/// Event emitted when a memo recompute raises a catchable error.
pub(all) struct MemoAbortedEvent {
  cell_id : CellId
  elapsed_ns : Int64
  started_revision : Revision
  error : Error
}

///|
/// Memo recompute lifecycle event delivered by `Runtime::on_memo_event`.
pub(all) enum MemoEvent {
  EnteringCompute(MemoEnteringEvent)
  Completed(MemoCompletedEvent)
  Aborted(MemoAbortedEvent)
}
