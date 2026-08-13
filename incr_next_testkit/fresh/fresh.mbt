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
/// Memo-free evaluator for the shared K1.1 operation and graph model.
///
/// This package deliberately has no dependency on `dowdiness/incr_next`.
pub fn evaluate(script : @model.Script) -> Array[@model.Observation] {
  let values : Map[Int, Int] = { 0: 0 }
  let observations : Array[@model.Observation] = []
  let reads = Ref(0)
  for operation in script.operations() {
    match operation {
      @model.Operation::Define(id, value) => values[id] = value
      @model.Operation::Set(id, value) => values[id] = value
      @model.Operation::Read(id) => {
        reads.val = reads.val + 1
        match scenario_value(values, script.scenario_tag(), id, 0) {
          Some(value) => observations.push(@model.Observation::Value(value))
          None => observations.push(@model.Observation::Missing(id))
        }
      }
      @model.Operation::ReadKey(id, key) => {
        reads.val = reads.val + 1
        match scenario_value(values, script.scenario_tag(), id, key) {
          Some(value) => observations.push(@model.Observation::Value(value))
          None => observations.push(@model.Observation::Missing(id))
        }
      }
      @model.Operation::DomainFailure(code) =>
        observations.push(
          @model.Observation::Error(@model.ScenarioError::DomainFailure(code)),
        )
      @model.Operation::StructuralFailure(code) =>
        observations.push(
          @model.Observation::Error(
            @model.ScenarioError::StructuralFailure(code),
          ),
        )
    }
  }
  observations.push(@model.Observation::Counter(reads.val))
  observations
}
