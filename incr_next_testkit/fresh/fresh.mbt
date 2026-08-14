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
  let values : Map[Int, Int] = match script.scenario_tag() {
    @model.Scenario::DynamicBranch => { 0: 0, 1: 0 }
    _ => { 0: 0 }
  }
  let observations : Array[@model.Observation] = []
  let computes = Ref(0)
  let change_epoch = Ref(0)
  let computed_epoch : Ref[Int?] = Ref(None)
  let keyed_computed : Map[(Int, Int), Bool] = Map([])
  for operation in script.operations() {
    match operation {
      @model.Operation::Define(id, value) | @model.Operation::Set(id, value) => {
        let existing = values.contains(id)
        values[id] = value
        if existing {
          change_epoch.val = change_epoch.val + 1
          computed_epoch.val = None
          keyed_computed.clear()
        }
      }
      @model.Operation::Read(id) => {
        let should_compute = match script.scenario_tag() {
          @model.Scenario::Source => false
          _ => computed_epoch.val != Some(change_epoch.val)
        }
        if should_compute {
          computes.val = computes.val +
            (match script.scenario_tag() {
              @model.Scenario::Chain => 2
              @model.Scenario::Diamond => 4
              _ => 1
            })
          computed_epoch.val = Some(change_epoch.val)
        }
        match scenario_value(values, script.scenario_tag(), id, 0) {
          Some(value) => observations.push(@model.Observation::Value(value))
          None => observations.push(@model.Observation::Missing(id))
        }
      }
      @model.Operation::ReadKey(id, key) => {
        let work = (id, key)
        if script.scenario_tag() is @model.Scenario::KeyedQuery &&
          !keyed_computed.contains(work) {
          computes.val = computes.val + 1
          keyed_computed[work] = true
        }
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
