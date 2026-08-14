///|
fn scenario_value(
  values : Map[Int, Int],
  scenario : @model.Scenario,
  source_id : Int,
  key : Int,
) -> Int? {
  let base = match values.get(source_id) {
    Some(value) => value
    None => return None
  }
  match scenario {
    @model.Scenario::Chain => Some(base + 1)
    @model.Scenario::Diamond => Some(base * 2 + 3)
    @model.Scenario::UnrelatedPublication
    | @model.Scenario::SelectedPublication => Some(base)
    @model.Scenario::FailureRecovery =>
      if base == 1 {
        None
      } else {
        Some(base)
      }
    @model.Scenario::DynamicBranch =>
      match values.get(1) {
        Some(flag) => if flag != 0 { Some(flag) } else { Some(base) }
        None => Some(base)
      }
    @model.Scenario::KeyedQuery => Some(base + key)
    @model.Scenario::Source => Some(base)
    _ => Some(base)
  }
}

///|
fn read_observation(
  values : Map[Int, Int],
  scenario : @model.Scenario,
  source_id : Int,
  key : Int,
) -> @model.Observation {
  match values.get(source_id) {
    None => @model.Observation::Missing(source_id)
    Some(base) if scenario == @model.Scenario::FailureRecovery && base == 1 =>
      @model.Observation::Error(@model.ScenarioError::StructuralFailure(1))
    Some(_) =>
      match scenario_value(values, scenario, source_id, key) {
        Some(value) => @model.Observation::Value(value)
        None => @model.Observation::Missing(source_id)
      }
  }
}

///|
fn from_scratch_read_work(scenario : @model.Scenario) -> Int {
  match scenario {
    @model.Scenario::Source => 0
    @model.Scenario::Chain => 2
    // The shared child is evaluated independently by each branch.
    @model.Scenario::Diamond => 5
    _ => 1
  }
}

///|
/// From-scratch evaluator for the shared operation and graph model.
///
/// This package deliberately has no dependency on `dowdiness/incr_next`.
/// Every read evaluates its graph anew; the final Counter is evidence of that
/// baseline, not part of the semantic oracle.
fn evaluate_acyclic(script : @model.Script) -> Array[@model.Observation] {
  let values : Map[Int, Int] = Map(
    script.initial_sources().map(init => (init.id, init.value)),
  )
  let observations : Array[@model.Observation] = []
  let computes = Ref(0)
  for operation in script.operations() {
    match operation {
      @model.Operation::Set(id, value) => values[id] = value
      @model.Operation::Read(id) => {
        computes.val = computes.val +
          from_scratch_read_work(script.scenario_tag())
        observations.push(
          read_observation(values, script.scenario_tag(), id, 0),
        )
      }
      @model.Operation::ReadKey(id, key) => {
        computes.val = computes.val +
          from_scratch_read_work(script.scenario_tag())
        observations.push(
          read_observation(values, script.scenario_tag(), id, key),
        )
      }
      @model.Operation::ReadQuery(_, _) =>
        abort("acyclic Fresh evaluator received ReadQuery")
      @model.Operation::DomainFailure(code) => {
        computes.val = computes.val + 1
        observations.push(
          @model.Observation::Error(@model.ScenarioError::DomainFailure(code)),
        )
      }
      @model.Operation::StructuralFailure(code) => {
        computes.val = computes.val + 1
        observations.push(
          @model.Observation::Error(
            @model.ScenarioError::StructuralFailure(code),
          ),
        )
      }
    }
  }
  observations.push(@model.Observation::Counter(computes.val))
  observations
}
