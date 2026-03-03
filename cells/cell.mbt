///|
// CellMeta and CellKind removed in Task 7 (SoA refactor).
// All cell metadata now lives in PullSignalData and PullMemoData
// in pull_signal.mbt and pull_memo.mbt respectively.
// The `using` declaration below provides unqualified access to @incr_types
// across the cells package.
using @incr_types { type CellId, type Durability, type Revision }
