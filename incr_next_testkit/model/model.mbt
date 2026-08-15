///|
/// Logical source identifier shared by Fresh and incremental adapters.
pub type SourceId = Int

///|
/// Logical Query identifier shared by Fresh and incremental adapters.
pub type QueryId = Int

///|
/// Fixed cutoff choices used by the independent K1.4 workloads.
pub(all) enum CutoffKind {
  AlwaysChangedEquivalent
  EqEquivalent
  EqChanged
  TypeOwnedEquivalent
  TypeOwnedChanged
  DynamicEquivalent
  ConsecutiveEquivalent
} derive(Eq, Debug)

///|
/// A compact cutoff workload: each step publishes the trigger Source before
/// the evaluator reads the fixed Query key.
pub struct CutoffScript {
  priv kind : CutoffKind
  priv steps : Array[Int]
} derive(Debug)

///|
pub fn CutoffScript::CutoffScript(
  kind : CutoffKind,
  steps : Array[Int],
) -> CutoffScript {
  { kind, steps: steps.copy() }
}

///|
pub fn CutoffScript::kind(self : CutoffScript) -> CutoffKind {
  self.kind
}

///|
pub fn CutoffScript::steps(self : CutoffScript) -> Array[Int] {
  self.steps.copy()
}

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
  FailureRecovery
  DomainFailure
  StructuralError
  DirectCycle
  MutualCycle
  SameQueryKeyCycle
  FiniteRecursion
  UnequalKeyCrossQuery
  DeadCycleBranch
  CycleRecovery
  OldTraceCycle
  SequentialDuplicateRead
} derive(Eq, Debug)

///|
/// A logical source and its value at graph construction time.
pub(all) struct SourceInit {
  id : SourceId
  value : Int
} derive(Eq, Debug)

///|
/// A runtime operation over a graph whose Source membership is already fixed.
/// IDs are explicit so scenarios do not rely on evaluator-local allocation.
pub(all) enum Operation {
  Set(SourceId, Int)
  Read(SourceId)
  ReadKey(SourceId, Int)
  ReadQuery(QueryId, Int)
  DomainFailure(Int)
  StructuralFailure(Int)
} derive(Eq, Debug)

///|
fn required_initial_ids(scenario : Scenario) -> Array[SourceId] {
  match scenario {
    UnitQuery
    | Chain
    | Diamond
    | UnrelatedPublication
    | SelectedPublication
    | RootSnapshot
    | FailureRecovery => [0]
    DynamicBranch => [0, 1]
    Source
    | KeyedQuery
    | DomainFailure
    | StructuralError
    | DirectCycle
    | MutualCycle
    | SameQueryKeyCycle
    | FiniteRecursion
    | UnequalKeyCrossQuery
    | SequentialDuplicateRead => []
    DeadCycleBranch | CycleRecovery | OldTraceCycle => [0]
  }
}

///|
fn fixed_root_scenario(scenario : Scenario) -> Bool {
  match scenario {
    UnitQuery
    | Chain
    | Diamond
    | UnrelatedPublication
    | SelectedPublication
    | DynamicBranch
    | RootSnapshot
    | FailureRecovery => true
    Source
    | KeyedQuery
    | DomainFailure
    | StructuralError
    | DirectCycle
    | MutualCycle
    | SameQueryKeyCycle
    | FiniteRecursion
    | UnequalKeyCrossQuery
    | DeadCycleBranch
    | CycleRecovery
    | OldTraceCycle
    | SequentialDuplicateRead => false
  }
}

///|
fn operation_error(
  scenario : Scenario,
  ids : Set[SourceId],
  operation : Operation,
) -> String? {
  match operation {
    Set(id, _) if !ids.contains(id) =>
      Some("Set target is not an initial source: \{id}")
    Read(_) if scenario == KeyedQuery =>
      Some("KeyedQuery accepts ReadKey operations, not plain Read")
    Read(id) if fixed_root_scenario(scenario) && ids.contains(id) && id != 0 =>
      Some("fixed-root scenario cannot Read present non-root source: \{id}")
    ReadKey(_, _) if is_cycle_scenario(scenario) =>
      Some("cycle scenarios accept ReadQuery operations, not ReadKey")
    ReadKey(_, _) if scenario != KeyedQuery =>
      Some("ReadKey is only valid for KeyedQuery")
    ReadQuery(_, _) if !is_cycle_scenario(scenario) =>
      Some("ReadQuery is only valid for cycle scenarios")
    Read(_) if is_cycle_scenario(scenario) =>
      Some("cycle scenarios accept ReadQuery operations, not plain Read")
    DomainFailure(_) if scenario != DomainFailure =>
      Some("DomainFailure operation requires the DomainFailure scenario")
    StructuralFailure(_) if scenario != StructuralError =>
      Some("StructuralFailure operation requires the StructuralError scenario")
    _ => None
  }
}

///|
fn is_cycle_scenario(scenario : Scenario) -> Bool {
  match scenario {
    DirectCycle
    | MutualCycle
    | SameQueryKeyCycle
    | FiniteRecursion
    | UnequalKeyCrossQuery
    | DeadCycleBranch
    | CycleRecovery
    | OldTraceCycle
    | SequentialDuplicateRead => true
    _ => false
  }
}

///|
/// Validates the private script contract at both setup and replay boundaries.
/// Reads of absent IDs remain valid so evaluators can report `Missing`.
fn validate_script(
  scenario : Scenario,
  initial_sources : Array[SourceInit],
  operations : Array[Operation],
) -> String? {
  let ids : Set[SourceId] = Set([])
  let mut error : String? = None
  initial_sources.each(init => {
    match error {
      Some(_) => ()
      None =>
        if !ids.add_and_check(init.id) {
          error = Some("duplicate initial source id: \{init.id}")
        }
    }
  })
  required_initial_ids(scenario).each(id => {
    match error {
      Some(_) => ()
      None =>
        if !ids.contains(id) {
          error = Some("scenario requires initial source id: \{id}")
        }
    }
  })
  operations.each(operation => {
    match error {
      Some(_) => ()
      None =>
        match operation_error(scenario, ids, operation) {
          Some(message) => error = Some(message)
          None => ()
        }
    }
  })
  error
}

///|
/// A two-phase script shared by Fresh and incremental adapters.
pub struct Script {
  priv scenario : Scenario
  priv initial_sources : Array[SourceInit]
  priv operations : Array[Operation]
} derive(Debug)

///|
/// Creates a Source-oriented script after validating immutable membership.
/// Aborts on duplicate IDs, undefined Set targets, or incompatible operations.
pub fn Script::Script(
  initial_sources : Array[SourceInit],
  operations : Array[Operation],
) -> Script {
  match validate_script(Source, initial_sources, operations) {
    Some(error) => abort(error)
    None =>
      {
        scenario: Source,
        initial_sources: initial_sources.copy(),
        operations: operations.copy(),
      }
  }
}

///|
/// Creates a named graph script after validating immutable membership.
/// Aborts on missing setup IDs, duplicate IDs, undefined Set targets, or an
/// operation incompatible with the selected graph scenario.
pub fn Script::scenario(
  scenario : Scenario,
  initial_sources : Array[SourceInit],
  operations : Array[Operation],
) -> Script {
  match validate_script(scenario, initial_sources, operations) {
    Some(error) => abort(error)
    None =>
      {
        scenario,
        initial_sources: initial_sources.copy(),
        operations: operations.copy(),
      }
  }
}

///|
/// Returns the scenario tag without exposing mutable script state.
pub fn Script::scenario_tag(self : Script) -> Scenario {
  self.scenario
}

///|
/// Returns an owned initial-source snapshot for testkit evaluators.
pub fn Script::initial_sources(self : Script) -> Array[SourceInit] {
  self.initial_sources.copy()
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
  Marker(Int)
  Missing(SourceId)
  Error(ScenarioError)
  Counter(Int)
} derive(Eq, Debug)

///|
/// Domain and structural failures are normalized separately from values.
pub(all) enum ScenarioError {
  DomainFailure(Int)
  StructuralFailure(Int)
  Cycle(CycleWitness)
} derive(Eq, Debug)

///|
/// An opaque, normalized, key-free witness for a detected Query cycle.
pub struct CycleWitness {
  priv path : Array[QueryId]
} derive(Eq, Debug)

///|
/// Copies a logical Query path into an opaque cycle witness.
pub fn CycleWitness::CycleWitness(path : Array[QueryId]) -> CycleWitness {
  { path: path.copy() }
}

///|
/// Returns a defensive copy of the logical Query path.
pub fn CycleWitness::path(self : CycleWitness) -> Array[QueryId] {
  self.path.copy()
}
