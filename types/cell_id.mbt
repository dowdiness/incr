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
  runtime_id : Int
  id : Int
} derive(Eq, Debug)

///|
pub impl Show for CellId with output(self, logger) {
  logger.write_string(@debug.to_string(self))
}

///|
pub impl Hash for CellId with hash(self) {
  self.runtime_id.hash() * 31 + self.id.hash()
}

///|
pub impl Hash for CellId with hash_combine(self, hasher) {
  self.runtime_id.hash_combine(hasher)
  self.id.hash_combine(hasher)
}
