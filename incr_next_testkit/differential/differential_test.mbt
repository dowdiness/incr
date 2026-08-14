///|
fn work_counter(observations : Array[@model.Observation]) -> Int {
  match observations.pop() {
    Some(@model.Observation::Counter(work)) => work
    _ => abort("expected one trailing Counter observation")
  }
}

///|
fn assert_semantics_and_work(
  script : @model.Script,
  expected : Array[@model.Observation],
  fresh_work : Int,
  incremental_work : Int,
) -> Unit raise {
  let fresh = @fresh.evaluate(script)
  let incremental = @incremental_adapter.evaluate(script)
  let actual_fresh_work = work_counter(fresh)
  let actual_incremental_work = work_counter(incremental)
  assert_eq(fresh, expected)
  assert_eq(incremental, expected)
  assert_eq(actual_fresh_work, fresh_work)
  assert_eq(actual_incremental_work, incremental_work)
}

///|
test "all K1.1 graph and error scenarios match Fresh semantically" {
  assert_true(@differential.all_match())
}

///|
test "Fresh and incremental work counters are separate evidence" {
  assert_semantics_and_work(
    @scenarios.canonical(),
    [@model.Observation::Value(0), @model.Observation::Value(4)],
    0,
    0,
  )
  assert_semantics_and_work(
    @scenarios.unit_query(),
    [@model.Observation::Value(0), @model.Observation::Value(0)],
    2,
    1,
  )
  assert_semantics_and_work(
    @scenarios.keyed_query(),
    [@model.Observation::Value(3), @model.Observation::Value(3)],
    2,
    1,
  )
  assert_semantics_and_work(
    @scenarios.chain(),
    [@model.Observation::Value(1), @model.Observation::Value(1)],
    4,
    2,
  )
  assert_semantics_and_work(
    @scenarios.diamond(),
    [@model.Observation::Value(3), @model.Observation::Value(3)],
    10,
    4,
  )
  assert_semantics_and_work(
    @scenarios.unrelated_publication(),
    [@model.Observation::Value(0), @model.Observation::Value(0)],
    2,
    1,
  )
  assert_semantics_and_work(
    @scenarios.selected_publication(),
    [@model.Observation::Value(0), @model.Observation::Value(7)],
    2,
    2,
  )
  assert_semantics_and_work(
    @scenarios.dynamic_branch(),
    [@model.Observation::Value(0), @model.Observation::Value(9)],
    2,
    2,
  )
  assert_semantics_and_work(
    @scenarios.root_snapshot(),
    [@model.Observation::Value(2), @model.Observation::Value(5)],
    2,
    2,
  )
  assert_semantics_and_work(
    @scenarios.domain_failure(),
    [@model.Observation::Error(@model.ScenarioError::DomainFailure(17))],
    1,
    1,
  )
  assert_semantics_and_work(
    @scenarios.structural_error(),
    [@model.Observation::Error(@model.ScenarioError::StructuralFailure(23))],
    1,
    1,
  )
}

///|
test "keyed work identity includes SourceId and key" {
  let script = @model.Script::scenario(@model.Scenario::KeyedQuery, [
    @model.Operation::Define(1, 10),
    @model.Operation::ReadKey(0, 3),
    @model.Operation::ReadKey(1, 3),
    @model.Operation::ReadKey(1, 3),
  ])
  assert_semantics_and_work(
    script,
    [
      @model.Observation::Value(3),
      @model.Observation::Value(13),
      @model.Observation::Value(13),
    ],
    3,
    2,
  )
}

///|
test "unrelated publication green-verifies without extra kernel compute" {
  assert_semantics_and_work(
    @scenarios.unrelated_publication(),
    [@model.Observation::Value(0), @model.Observation::Value(0)],
    2,
    1,
  )
}

///|
test "selected publication red-recomputes with matching work" {
  assert_semantics_and_work(
    @scenarios.selected_publication(),
    [@model.Observation::Value(0), @model.Observation::Value(7)],
    2,
    2,
  )
}

///|
test "chain semantic values match without simulating memo work in Fresh" {
  assert_semantics_and_work(
    @scenarios.chain(),
    [@model.Observation::Value(1), @model.Observation::Value(1)],
    4,
    2,
  )
}

///|
test "diamond semantic values match without simulating memo work in Fresh" {
  assert_semantics_and_work(
    @scenarios.diamond(),
    [@model.Observation::Value(3), @model.Observation::Value(3)],
    10,
    4,
  )
}

///|
test "UnitQuery Define publishes an existing Source" {
  let script = @model.Script::scenario(@model.Scenario::UnitQuery, [
    @model.Operation::Read(0),
    @model.Operation::Define(0, 7),
    @model.Operation::Read(0),
  ])
  assert_semantics_and_work(
    script,
    [@model.Observation::Value(0), @model.Observation::Value(7)],
    2,
    2,
  )
}

///|
test "DynamicBranch late Define publishes a pre-existing default Source" {
  assert_semantics_and_work(
    @scenarios.dynamic_branch(),
    [@model.Observation::Value(0), @model.Observation::Value(9)],
    2,
    2,
  )
}
