///|
/// A unique identifier for a cell (signal or memo) in the runtime.
///
/// Cell IDs are monotonically increasing integers allocated by the runtime.
/// They serve as direct array indices for O(1) cell lookup.
///
/// Each CellId is scoped to its originating runtime via `runtime_id`.
/// This prevents cells from different runtimes being incorrectly queried
/// against each other.
pub(all) struct CellId {
  runtime_id : RuntimeId
  id : Int
} derive(Eq, Debug)
pub extend CellId with Eq::{not_equal, equal}
pub extend CellId with Debug::{to_repr}
pub extend CellId with Show::{output, to_string}
pub extend CellId with Hash::{hash, hash_combine}

///|
pub impl Show for CellId with fn output(self, logger) {
  logger.write_string(@debug.to_string(self))
}

///|
pub impl Hash for CellId with fn hash(self) {
  Hash::hash(self.runtime_id) * 31 + self.id.hash()
}

///|
pub impl Hash for CellId with fn hash_combine(self, hasher) {
  Hash::hash_combine(Hash::hash(self), hasher)
}
