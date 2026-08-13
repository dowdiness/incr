///|
/// Logical source identifier shared by Fresh and incremental adapters.
pub type SourceId = Int

///|
/// A small K1.1 operation script.
pub(all) enum Operation {
  Set(SourceId, Int)
  Read(SourceId)
} derive(Eq, Debug)

///|
/// A script's normalized observations.
pub struct Script {
  operations : Array[Operation]
} derive(Debug)

///|
/// Creates a script without exposing an evaluator or kernel capability.
pub fn Script::Script(operations : Array[Operation]) -> Script {
  { operations, }
}

///|
/// A normalized observation used by differential tests.
pub(all) enum Observation {
  Value(Int)
  Missing(SourceId)
} derive(Eq, Debug)
