///|
/// Event emitted when a derived recompute starts.
pub(all) struct DerivedEnteringEvent {
  cell_id : CellId
  started_revision : Revision
}

///|
/// Event emitted when a derived recompute completes successfully.
pub(all) struct DerivedCompletedEvent {
  cell_id : CellId
  elapsed_ns : Int64
  started_revision : Revision
  verified_at : Revision
  changed_at : Revision
  backdated : Bool
}

///|
/// Event emitted when a derived recompute raises a catchable error.
pub(all) struct DerivedAbortedEvent {
  cell_id : CellId
  elapsed_ns : Int64
  started_revision : Revision
  error : Error
}

///|
/// Derived recompute lifecycle event delivered by `Runtime::on_derived_event`.
pub(all) enum DerivedEvent {
  EnteringCompute(DerivedEnteringEvent)
  Completed(DerivedCompletedEvent)
  Aborted(DerivedAbortedEvent)
}
