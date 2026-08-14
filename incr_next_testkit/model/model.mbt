///|
/// Logical source identifier shared by Fresh and incremental adapters.
pub type SourceId = Int

///|
/// Graph shape exercised by a differential script.
pub(all) enum Scenario {
  Source
  UnitQuery
  KeyedQuery
  Chain
  Diamond
  UnrelatedPublication
  SelectedPublication
  DynamicBranch
  RootSnapshot
  DomainFailure
  StructuralError
} derive(Eq, Debug)

///|
/// A logical K1.1 operation. IDs are explicit so scenarios can use more than
/// one Source without relying on evaluator-local allocation order.
pub(all) enum Operation {
  Define(SourceId, Int)
  Set(SourceId, Int)
  Read(SourceId)
  ReadKey(SourceId, Int)
  DomainFailure(Int)
  StructuralFailure(Int)
} derive(Eq, Debug)

///|
/// A snapshot-safe operation script shared by Fresh and incremental adapters.
pub struct Script {
  priv scenario : Scenario
  priv operations : Array[Operation]
} derive(Debug)

///|
/// Creates a Source-oriented script. The input array is copied at the seam.
pub fn Script::Script(operations : Array[Operation]) -> Script {
  { scenario: Source, operations: operations.copy() }
}

///|
/// Creates a script for one named graph scenario.
pub fn Script::scenario(
  scenario : Scenario,
  operations : Array[Operation],
) -> Script {
  { scenario, operations: operations.copy() }
}

///|
/// Returns the scenario tag without exposing the mutable operation array.
pub fn Script::scenario_tag(self : Script) -> Scenario {
  self.scenario
}

///|
/// Returns an owned operation snapshot for testkit evaluators.
pub fn Script::operations(self : Script) -> Array[Operation] {
  self.operations.copy()
}

///|
/// A normalized observation used by differential tests.
pub(all) enum Observation {
  Value(Int)
  Missing(SourceId)
  Error(ScenarioError)
  Counter(Int)
} derive(Eq, Debug)

///|
/// Domain and structural failures are normalized separately from values.
pub(all) enum ScenarioError {
  DomainFailure(Int)
  StructuralFailure(Int)
} derive(Eq, Debug)
