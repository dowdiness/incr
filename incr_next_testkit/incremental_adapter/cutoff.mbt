///|
priv struct CutoffValue {
  value : Int
  marker : Int
}

///|
impl Eq for CutoffValue with fn equal(self, other) {
  self.value == other.value
}

///|
impl @incr_next.CutoffEq for CutoffValue with fn cutoff_equal(self, other) {
  self.value == other.value
}

///|
fn cutoff_observation_value(kind : @model.CutoffKind, step : Int) -> Int {
  match kind {
    @model.CutoffKind::EqChanged | @model.CutoffKind::TypeOwnedChanged => step
    _ => 0
  }
}

///|
/// Runs the same cutoff workload against the independent kernel adapter.
pub fn evaluate_cutoff(
  script : @model.CutoffScript,
) -> Array[@model.Observation] {
  let store = @incr_next.Store::Store()
  let region = store.region().unwrap()
  let trigger = region.source(0).unwrap()
  let query : (Unit) -> Result[CutoffValue, @incr_next.ReadError] = match
    script.kind() {
    @model.CutoffKind::AlwaysChangedEquivalent => {
      let query = region
        .query_always_changed((ctx, _unit : Unit) => {
          match ctx.read(trigger.view()) {
            Ok(step) => Ok(CutoffValue::{ value: 0, marker: step })
            Err(error) => Err(error)
          }
        })
        .unwrap()
      unit => store.read(query.at(unit))
    }
    @model.CutoffKind::EqEquivalent => {
      let query = region
        .query_eq((ctx, _unit : Unit) => {
          match ctx.read(trigger.view()) {
            Ok(step) => Ok(CutoffValue::{ value: 0, marker: step })
            Err(error) => Err(error)
          }
        })
        .unwrap()
      unit => store.read(query.at(unit))
    }
    @model.CutoffKind::ConsecutiveEquivalent => {
      let query = region
        .query_type_owned((ctx, _unit : Unit) => {
          match ctx.read(trigger.view()) {
            Ok(step) => Ok(CutoffValue::{ value: 0, marker: step })
            Err(error) => Err(error)
          }
        })
        .unwrap()
      unit => store.read(query.at(unit))
    }
    @model.CutoffKind::EqChanged => {
      let query = region
        .query_eq((ctx, _unit : Unit) => {
          match ctx.read(trigger.view()) {
            Ok(step) => Ok(CutoffValue::{ value: step, marker: step })
            Err(error) => Err(error)
          }
        })
        .unwrap()
      unit => store.read(query.at(unit))
    }
    @model.CutoffKind::TypeOwnedEquivalent
    | @model.CutoffKind::TypeOwnedChanged => {
      let kind = script.kind()
      let query = region
        .query_type_owned((ctx, _unit : Unit) => {
          match ctx.read(trigger.view()) {
            Ok(step) =>
              Ok(CutoffValue::{
                value: cutoff_observation_value(kind, step),
                marker: step,
              })
            Err(error) => Err(error)
          }
        })
        .unwrap()
      unit => store.read(query.at(unit))
    }
    @model.CutoffKind::DynamicEquivalent => {
      let old_branch = region.source(0).unwrap()
      let new_branch = region.source(0).unwrap()
      let query = region
        .query_eq((ctx, _unit : Unit) => {
          match ctx.read(trigger.view()) {
            Ok(flag) => {
              let value = if flag == 0 {
                ctx.read(old_branch.view())
              } else {
                ctx.read(new_branch.view())
              }
              value.map(value => CutoffValue::{ value, marker: flag })
            }
            Err(error) => Err(error)
          }
        })
        .unwrap()
      unit => store.read(query.at(unit))
    }
  }
  let observations : Array[@model.Observation] = []
  for step in script.steps() {
    match store.transaction(tx => tx.set(trigger, step)) {
      Ok(_) => ()
      Err(_) => abort("valid cutoff publication failed unexpectedly")
    }
    match query(()) {
      Ok(value) => {
        observations.push(@model.Observation::Value(value.value))
        match script.kind() {
          @model.CutoffKind::TypeOwnedEquivalent
          | @model.CutoffKind::TypeOwnedChanged
          | @model.CutoffKind::ConsecutiveEquivalent =>
            observations.push(@model.Observation::Marker(value.marker))
          _ => ()
        }
      }
      Err(_) => observations.push(@model.Observation::Missing(0))
    }
  }
  ignore(region.close())
  observations
}
