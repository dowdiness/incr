///|
pub using @incr_types {
  type Revision,
  type Durability,
  type CellId,
  DURABILITY_COUNT,
}

///|
pub using @internal {
  type Runtime,
  type CellInfo,
  type Signal,
  type Memo,
  type CycleError,
  type TrackedCell,
}

// Traits and helper functions (IncrDb, Readable, Trackable, create_signal,
// create_memo, create_tracked_cell, batch, gc_tracked) are defined in
// traits.mbt and are part of this package's public API.
