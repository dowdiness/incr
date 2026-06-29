///|
// CellMeta and CellKind removed in Task 7 (SoA refactor).
// All cell metadata now lives in PullInputData and MemoData
// in internal/pull/pull_input.mbt and internal/pull/memo_data.mbt respectively.
// The `using` declaration below provides unqualified access to @incr_types
// across the cells package.
pub using @incr_types {
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
