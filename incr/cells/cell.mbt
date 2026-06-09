///|
// CellMeta and CellKind removed in Task 7 (SoA refactor).
// All cell metadata now lives in PullSignalData and MemoData
// in internal/pull/pull_signal.mbt and internal/pull/memo_data.mbt respectively.
// The `using` declaration below provides unqualified access to @incr_types
// across the cells package.
using @incr_types {
  type CellId,
  type CycleError,
  type ReadError,
  type Durability,
  type Revision,
  type ListenerId,
  trait BackdateEq,
}

///|
using @shared {type CellRef}
