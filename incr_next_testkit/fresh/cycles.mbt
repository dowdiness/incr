///|
/// Fresh's typed identity keeps Query equality and key equality together.
priv struct FreshInvocation {
  query_id : @model.QueryId
  key : Int
} derive(Eq, Hash)

///|
/// State owned entirely by the Fresh evaluator for one script replay.
priv struct FreshQueryState {
  values : Map[@model.SourceId, Int]
  active : Map[FreshInvocation, Int]
  stack : Array[@model.QueryId]
  computes : Ref[Int]
}

///|
/// Projects the active key-sensitive stack into a copied logical witness.
fn cycle_witness(
  stack : Array[@model.QueryId],
  start : Int,
  query_id : @model.QueryId,
) -> @model.CycleWitness {
  let path = stack[start:].map(id => id)
  path.push(query_id)
  @model.CycleWitness(path)
}

///|
/// Evaluates one Fresh Query recursively with invocation-level cycle tracking.
fn fresh_query(
  state : FreshQueryState,
  scenario : @model.Scenario,
  query_id : @model.QueryId,
  key : Int,
) -> Result[Int, @model.ScenarioError] {
  let invocation = FreshInvocation::{ query_id, key }
  match state.active.get(invocation) {
    Some(start) =>
      Err(
        @model.ScenarioError::Cycle(cycle_witness(state.stack, start, query_id)),
      )
    None => {
      state.active.set(invocation, state.stack.length())
      state.stack.push(query_id)
      state.computes.val = state.computes.val + 1
      let result : Result[Int, @model.ScenarioError] = match scenario {
        @model.Scenario::DirectCycle =>
          fresh_query(state, scenario, query_id, key)
        @model.Scenario::MutualCycle =>
          if query_id == 0 {
            fresh_query(state, scenario, 1, key)
          } else {
            fresh_query(state, scenario, 0, key)
          }
        @model.Scenario::SameQueryKeyCycle =>
          if key == 0 {
            fresh_query(state, scenario, query_id, 1)
          } else {
            fresh_query(state, scenario, query_id, 0)
          }
        @model.Scenario::FiniteRecursion =>
          if key > 0 {
            fresh_query(state, scenario, query_id, key - 1)
          } else {
            Ok(0)
          }
        @model.Scenario::UnequalKeyCrossQuery =>
          if query_id == 0 && key == 0 {
            fresh_query(state, scenario, 1, key)
          } else if query_id == 1 && key == 0 {
            fresh_query(state, scenario, 0, 1)
          } else {
            Ok(key)
          }
        @model.Scenario::DeadCycleBranch => {
          let source = state.values[0]
          if source == 0 {
            Ok(source)
          } else {
            fresh_query(state, scenario, query_id, key)
          }
        }
        @model.Scenario::CycleRecovery => {
          let source = state.values[0]
          if source == 1 {
            fresh_query(state, scenario, query_id, key)
          } else {
            Ok(source)
          }
        }
        @model.Scenario::OldTraceCycle =>
          if query_id == 0 {
            if state.values[0] == 0 {
              Ok(0)
            } else {
              fresh_query(state, scenario, 1, key)
            }
          } else if state.values[0] == 0 {
            fresh_query(state, scenario, 0, key)
          } else {
            Ok(state.values[0])
          }
        @model.Scenario::SequentialDuplicateRead =>
          if query_id == 0 {
            match fresh_query(state, scenario, 1, key) {
              Ok(first) =>
                match fresh_query(state, scenario, 1, key) {
                  Ok(second) => Ok(first + second)
                  Err(error) => Err(error)
                }
              Err(error) => Err(error)
            }
          } else {
            Ok(0)
          }
        _ => abort("Fresh cycle evaluator received a non-cycle scenario")
      }
      ignore(state.stack.pop())
      state.active.remove(invocation)
      result
    }
  }
}

///|
fn evaluate_cycles(script : @model.Script) -> Array[@model.Observation] {
  let state = FreshQueryState::{
    values: Map(script.initial_sources().map(init => (init.id, init.value))),
    active: Map([]),
    stack: [],
    computes: Ref(0),
  }
  let observations : Array[@model.Observation] = []
  for operation in script.operations() {
    match operation {
      @model.Operation::Set(id, value) => state.values[id] = value
      @model.Operation::ReadQuery(query_id, key) =>
        match fresh_query(state, script.scenario_tag(), query_id, key) {
          Ok(value) => observations.push(@model.Observation::Value(value))
          Err(error) => observations.push(@model.Observation::Error(error))
        }
      _ => abort("cycle scenario contains a non-query operation")
    }
  }
  observations.push(@model.Observation::Counter(state.computes.val))
  observations
}

///|
/// Evaluates either the original acyclic workload or the K1.3 cycle matrix.
pub fn evaluate(script : @model.Script) -> Array[@model.Observation] {
  match script.scenario_tag() {
    @model.Scenario::DirectCycle
    | @model.Scenario::MutualCycle
    | @model.Scenario::SameQueryKeyCycle
    | @model.Scenario::FiniteRecursion
    | @model.Scenario::UnequalKeyCrossQuery
    | @model.Scenario::DeadCycleBranch
    | @model.Scenario::CycleRecovery
    | @model.Scenario::OldTraceCycle
    | @model.Scenario::SequentialDuplicateRead => evaluate_cycles(script)
    _ => evaluate_acyclic(script)
  }
}
