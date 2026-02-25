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
  type MemoMap,
  type CycleError,
  type TrackedCell,
}

// Note: @internal alias above refers to dowdiness/incr/cells (renamed from
// internal/ to enable pub using to work for external consumers who import
// dowdiness/incr). The alias name @internal is preserved for source compat.

// Traits and helper functions (Database, Readable, Trackable, create_signal,
// create_memo, create_memo_map, create_tracked_cell, batch, gc_tracked) are
// defined in traits.mbt and are part of this package's public API.
