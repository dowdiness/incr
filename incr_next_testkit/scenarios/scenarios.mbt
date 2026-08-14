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
/// A direct self-cycle, `A(0) -> A(0)`.
pub fn direct_cycle() -> @model.Script {
  script(@model.Scenario::DirectCycle, [], [@model.Operation::ReadQuery(0, 0)])
}

///|
/// A mutual cycle, `A(0) -> B(0) -> A(0)`.
pub fn mutual_cycle() -> @model.Script {
  script(@model.Scenario::MutualCycle, [], [@model.Operation::ReadQuery(0, 0)])
}

///|
/// A same-Query key cycle, `Q(0) -> Q(1) -> Q(0)`.
pub fn same_query_key_cycle() -> @model.Script {
  script(@model.Scenario::SameQueryKeyCycle, [], [
    @model.Operation::ReadQuery(0, 0),
  ])
}

///|
/// Finite keyed recursion, `Q(3) -> ... -> Q(0)`.
pub fn finite_recursion() -> @model.Script {
  script(@model.Scenario::FiniteRecursion, [], [
    @model.Operation::ReadQuery(0, 3),
  ])
}

///|
/// Unequal-key cross-Query recursion, `A(0) -> B(0) -> A(1)`.
pub fn unequal_key_cross_query() -> @model.Script {
  script(@model.Scenario::UnequalKeyCrossQuery, [], [
    @model.Operation::ReadQuery(0, 0),
  ])
}

///|
/// A source-controlled branch whose cycle is dead when source `0` is zero.
pub fn dead_cycle_branch() -> @model.Script {
  script(
    @model.Scenario::DeadCycleBranch,
    [@model.SourceInit::{ id: 0, value: 0 }],
    [@model.Operation::ReadQuery(0, 0)],
  )
}

///|
/// Introduces a cycle, repeats it, then recovers after a later publication.
pub fn cycle_recovery() -> @model.Script {
  script(
    @model.Scenario::CycleRecovery,
    [@model.SourceInit::{ id: 0, value: 0 }],
    [
      @model.Operation::ReadQuery(0, 0),
      @model.Operation::Set(0, 1),
      @model.Operation::ReadQuery(0, 0),
      @model.Operation::ReadQuery(0, 0),
      @model.Operation::Set(0, 2),
      @model.Operation::ReadQuery(0, 0),
    ],
  )
}

///|
/// Establishes `B -> A` before switching to `A -> B` whose current B branch
/// avoids A.
pub fn old_trace_cycle() -> @model.Script {
  script(
    @model.Scenario::OldTraceCycle,
    [@model.SourceInit::{ id: 0, value: 0 }],
    [
      @model.Operation::ReadQuery(1, 0),
      @model.Operation::Set(0, 1),
      @model.Operation::ReadQuery(0, 0),
    ],
  )
}

///|
/// A sequential duplicate child read, `A -> B` followed by `A -> B`.
pub fn sequential_duplicate_read() -> @model.Script {
  script(@model.Scenario::SequentialDuplicateRead, [], [
    @model.Operation::ReadQuery(0, 0),
  ])
}

///|
/// Returns the independent K1.3 cycle matrix. These scripts are intentionally
/// excluded from `all` until the incremental adapter implements cycles.
pub fn cycle_matrix() -> Array[@model.Script] {
  [
    direct_cycle(),
    mutual_cycle(),
    same_query_key_cycle(),
    finite_recursion(),
    unequal_key_cross_query(),
    dead_cycle_branch(),
    cycle_recovery(),
    old_trace_cycle(),
    sequential_duplicate_read(),
  ]
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
