///|
/// A unique identifier for an Accumulator in the runtime.
///
/// Monotonically allocated by the runtime; never reused across dispose/new.
/// Stale references to disposed accumulators resolve to "slot disposed" at
/// verify time rather than aliasing to a recycled slot.
///
/// Each AccumulatorId is scoped to its originating runtime via `runtime_id`.
pub(all) struct AccumulatorId {
  runtime_id : RuntimeId
  id : Int
} derive(Eq, Debug)
pub extend AccumulatorId with Eq::{not_equal, equal}
pub extend AccumulatorId with Debug::{to_repr}
pub extend AccumulatorId with Show::{output, to_string}
pub extend AccumulatorId with Hash::{hash, hash_combine}

///|
pub impl Show for AccumulatorId with fn output(self, logger) {
  logger.write_string(@debug.to_string(self))
}

///|
pub impl Hash for AccumulatorId with fn hash(self) {
  Hash::hash(self.runtime_id) * 31 + self.id.hash()
}

///|
pub impl Hash for AccumulatorId with fn hash_combine(self, hasher) {
  Hash::hash_combine(Hash::hash(self), hasher)
}
