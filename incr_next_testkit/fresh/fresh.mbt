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
pub fn evaluate(script : @model.Script) -> Array[@model.Observation] {
  let values : Map[Int, Int] = match script.scenario_tag() {
    @model.Scenario::DynamicBranch
    | @model.Scenario::UnrelatedPublication
    | @model.Scenario::SelectedPublication => { 0: 0, 1: 0 }
    _ => { 0: 0 }
  }
  let observations : Array[@model.Observation] = []
  let computes = Ref(0)
  for operation in script.operations() {
    match operation {
      @model.Operation::Define(id, value) | @model.Operation::Set(id, value) =>
        values[id] = value
      @model.Operation::Read(id) => {
        computes.val = computes.val +
          from_scratch_read_work(script.scenario_tag())
        match scenario_value(values, script.scenario_tag(), id, 0) {
          Some(value) => observations.push(@model.Observation::Value(value))
          None => observations.push(@model.Observation::Missing(id))
        }
      }
      @model.Operation::ReadKey(id, key) => {
        computes.val = computes.val +
          from_scratch_read_work(script.scenario_tag())
        match scenario_value(values, script.scenario_tag(), id, key) {
          Some(value) => observations.push(@model.Observation::Value(value))
          None => observations.push(@model.Observation::Missing(id))
        }
      }
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
