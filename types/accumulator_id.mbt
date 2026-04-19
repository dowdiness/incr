///|
/// A unique identifier for an Accumulator in the runtime.
///
/// Monotonically allocated by the runtime; never reused across dispose/new.
/// Stale references to disposed accumulators resolve to "slot disposed" at
/// verify time rather than aliasing to a recycled slot.
///
/// Each AccumulatorId is scoped to its originating runtime via `runtime_id`.
pub(all) struct AccumulatorId {
  runtime_id : Int
  id : Int
} derive(Eq, Debug)

///|
pub impl Show for AccumulatorId with output(self, logger) {
  logger.write_string(@debug.to_string(self))
}

///|
pub impl Hash for AccumulatorId with hash(self) {
  self.runtime_id.hash() * 31 + self.id.hash()
}

///|
pub impl Hash for AccumulatorId with hash_combine(self, hasher) {
  self.runtime_id.hash_combine(hasher)
  self.id.hash_combine(hasher)
}
