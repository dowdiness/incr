///|
fn fresh_work(observations : Array[@model.Observation]) -> Int {
  match observations.pop() {
    Some(@model.Observation::Counter(work)) => work
    _ => abort("expected one trailing Counter observation")
  }
}

///|
test "Fresh cycle matrix has exact witnesses, values, and work" {
  let direct = @fresh.evaluate(@scenarios.direct_cycle())
  assert_eq(direct, [
    @model.Observation::Error(
      @model.ScenarioError::Cycle(@model.CycleWitness::CycleWitness([0, 0])),
    ),
    @model.Observation::Counter(1),
  ])
  assert_eq(fresh_work(@fresh.evaluate(@scenarios.direct_cycle())), 1)

  assert_eq(@fresh.evaluate(@scenarios.mutual_cycle()), [
    @model.Observation::Error(
      @model.ScenarioError::Cycle(@model.CycleWitness::CycleWitness([0, 1, 0])),
    ),
    @model.Observation::Counter(2),
  ])
  assert_eq(@fresh.evaluate(@scenarios.same_query_key_cycle()), [
    @model.Observation::Error(
      @model.ScenarioError::Cycle(@model.CycleWitness::CycleWitness([0, 0, 0])),
    ),
    @model.Observation::Counter(2),
  ])
  assert_eq(@fresh.evaluate(@scenarios.finite_recursion()), [
    @model.Observation::Value(0),
    @model.Observation::Counter(4),
  ])
  assert_eq(@fresh.evaluate(@scenarios.unequal_key_cross_query()), [
    @model.Observation::Value(1),
    @model.Observation::Counter(3),
  ])
  assert_eq(@fresh.evaluate(@scenarios.dead_cycle_branch()), [
    @model.Observation::Value(0),
    @model.Observation::Counter(1),
  ])
  assert_eq(@fresh.evaluate(@scenarios.sequential_duplicate_read()), [
    @model.Observation::Value(0),
    @model.Observation::Counter(3),
  ])
}

///|
test "Fresh cycle errors are not cached and recovery uses current state" {
  assert_eq(@fresh.evaluate(@scenarios.cycle_recovery()), [
    @model.Observation::Value(0),
    @model.Observation::Error(
      @model.ScenarioError::Cycle(@model.CycleWitness::CycleWitness([0, 0])),
    ),
    @model.Observation::Error(
      @model.ScenarioError::Cycle(@model.CycleWitness::CycleWitness([0, 0])),
    ),
    @model.Observation::Value(2),
    @model.Observation::Counter(4),
  ])
}

///|
test "Fresh old-trace cycle uses current branch semantics" {
  assert_eq(@fresh.evaluate(@scenarios.old_trace_cycle()), [
    @model.Observation::Value(0),
    @model.Observation::Value(1),
    @model.Observation::Counter(4),
  ])
}
