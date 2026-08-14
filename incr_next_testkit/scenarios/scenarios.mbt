///|
fn script(
  scenario : @model.Scenario,
  initial_sources : Array[@model.SourceInit],
  operations : Array[@model.Operation],
) -> @model.Script {
  @model.Script::scenario(scenario, initial_sources, operations)
}

///|
/// Canonical Source read/update/read workload.
pub fn canonical() -> @model.Script {
  script(@model.Scenario::Source, [@model.SourceInit::{ id: 0, value: 0 }], [
    @model.Operation::Read(0),
    @model.Operation::Set(0, 4),
    @model.Operation::Read(0),
  ])
}

///|
/// A unit-keyed Query that reads the required root Source.
pub fn unit_query() -> @model.Script {
  script(@model.Scenario::UnitQuery, [@model.SourceInit::{ id: 0, value: 0 }], [
    @model.Operation::Read(0),
    @model.Operation::Read(0),
  ])
}

///|
/// A keyed Query whose Source identity and integer key both affect the value.
pub fn keyed_query() -> @model.Script {
  script(
    @model.Scenario::KeyedQuery,
    [
      @model.SourceInit::{ id: 0, value: 0 },
      @model.SourceInit::{ id: 1, value: 10 },
    ],
    [
      @model.Operation::ReadKey(0, 3),
      @model.Operation::ReadKey(1, 3),
      @model.Operation::ReadKey(1, 3),
    ],
  )
}

///|
/// A two-level Query chain rooted at Source `0`.
pub fn chain() -> @model.Script {
  script(@model.Scenario::Chain, [@model.SourceInit::{ id: 0, value: 0 }], [
    @model.Operation::Read(0),
    @model.Operation::Read(0),
  ])
}

///|
/// A shared-child diamond rooted at Source `0`.
pub fn diamond() -> @model.Script {
  script(@model.Scenario::Diamond, [@model.SourceInit::{ id: 0, value: 0 }], [
    @model.Operation::Read(0),
    @model.Operation::Read(0),
  ])
}

///|
/// Publishes an unrelated initial Source while reading root Source `0`.
pub fn unrelated_publication() -> @model.Script {
  script(
    @model.Scenario::UnrelatedPublication,
    [
      @model.SourceInit::{ id: 0, value: 0 },
      @model.SourceInit::{ id: 1, value: 0 },
    ],
    [
      @model.Operation::Read(0),
      @model.Operation::Set(1, 7),
      @model.Operation::Read(0),
    ],
  )
}

///|
/// Publishes the selected root Source and reads its updated value.
pub fn selected_publication() -> @model.Script {
  script(
    @model.Scenario::SelectedPublication,
    [@model.SourceInit::{ id: 0, value: 0 }],
    [
      @model.Operation::Read(0),
      @model.Operation::Set(0, 7),
      @model.Operation::Read(0),
    ],
  )
}

///|
/// Switches a Query between the required base and branch Sources.
pub fn dynamic_branch() -> @model.Script {
  script(
    @model.Scenario::DynamicBranch,
    [
      @model.SourceInit::{ id: 0, value: 0 },
      @model.SourceInit::{ id: 1, value: 0 },
    ],
    [
      @model.Operation::Read(0),
      @model.Operation::Set(1, 9),
      @model.Operation::Read(0),
      @model.Operation::Set(0, 7),
      @model.Operation::Read(0),
    ],
  )
}

///|
/// Reads the root after two transactional revisions.
pub fn root_snapshot() -> @model.Script {
  script(
    @model.Scenario::RootSnapshot,
    [@model.SourceInit::{ id: 0, value: 0 }],
    [
      @model.Operation::Set(0, 2),
      @model.Operation::Read(0),
      @model.Operation::Set(0, 5),
      @model.Operation::Read(0),
    ],
  )
}

///|
/// Exercises a closed structural dependency between successful reads.
pub fn failure_recovery() -> @model.Script {
  script(
    @model.Scenario::FailureRecovery,
    [@model.SourceInit::{ id: 0, value: 0 }],
    [
      @model.Operation::Read(0),
      @model.Operation::Set(0, 1),
      @model.Operation::Read(0),
      @model.Operation::Set(0, 2),
      @model.Operation::Read(0),
    ],
  )
}

///|
/// Invokes the prepared domain-error capability with code `17`.
pub fn domain_failure() -> @model.Script {
  script(@model.Scenario::DomainFailure, [], [
    @model.Operation::DomainFailure(17),
  ])
}

///|
/// Invokes the prepared cross-store capability with code `23`.
pub fn structural_error() -> @model.Script {
  script(@model.Scenario::StructuralError, [], [
    @model.Operation::StructuralFailure(23),
  ])
}

///|
/// Returns every canonical graph and error scenario in test order.
pub fn all() -> Array[@model.Script] {
  [
    canonical(),
    unit_query(),
    keyed_query(),
    chain(),
    diamond(),
    unrelated_publication(),
    selected_publication(),
    dynamic_branch(),
    root_snapshot(),
    failure_recovery(),
    domain_failure(),
    structural_error(),
  ]
}
