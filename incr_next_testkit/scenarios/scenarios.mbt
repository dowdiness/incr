///|
fn script(
  scenario : @model.Scenario,
  operations : Array[@model.Operation],
) -> @model.Script {
  @model.Script::scenario(scenario, operations)
}

///|
/// Canonical Source read/update/read workload.
pub fn canonical() -> @model.Script {
  script(@model.Scenario::Source, [
    @model.Operation::Read(0),
    @model.Operation::Set(0, 4),
    @model.Operation::Read(0),
  ])
}

///|
pub fn unit_query() -> @model.Script {
  script(@model.Scenario::UnitQuery, [
    @model.Operation::Read(0),
    @model.Operation::Read(0),
  ])
}

///|
pub fn keyed_query() -> @model.Script {
  script(@model.Scenario::KeyedQuery, [
    @model.Operation::ReadKey(0, 3),
    @model.Operation::ReadKey(0, 3),
  ])
}

///|
pub fn chain() -> @model.Script {
  script(@model.Scenario::Chain, [
    @model.Operation::Read(0),
    @model.Operation::Read(0),
  ])
}

///|
pub fn diamond() -> @model.Script {
  script(@model.Scenario::Diamond, [
    @model.Operation::Read(0),
    @model.Operation::Read(0),
  ])
}

///|
pub fn unrelated_publication() -> @model.Script {
  script(@model.Scenario::UnrelatedPublication, [
    @model.Operation::Read(0),
    @model.Operation::Set(1, 7),
    @model.Operation::Read(0),
  ])
}

///|
pub fn selected_publication() -> @model.Script {
  script(@model.Scenario::SelectedPublication, [
    @model.Operation::Read(0),
    @model.Operation::Set(0, 7),
    @model.Operation::Read(0),
  ])
}

///|
pub fn dynamic_branch() -> @model.Script {
  script(@model.Scenario::DynamicBranch, [
    @model.Operation::Read(0),
    @model.Operation::Define(1, 9),
    @model.Operation::Read(0),
  ])
}

///|
pub fn root_snapshot() -> @model.Script {
  script(@model.Scenario::RootSnapshot, [
    @model.Operation::Define(0, 2),
    @model.Operation::Read(0),
    @model.Operation::Set(0, 5),
    @model.Operation::Read(0),
  ])
}

///|
pub fn domain_failure() -> @model.Script {
  script(@model.Scenario::DomainFailure, [@model.Operation::DomainFailure(17)])
}

///|
pub fn structural_error() -> @model.Script {
  script(@model.Scenario::StructuralError, [
    @model.Operation::StructuralFailure(23),
  ])
}

///|
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
    domain_failure(),
    structural_error(),
  ]
}
