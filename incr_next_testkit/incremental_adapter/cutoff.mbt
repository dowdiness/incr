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
) -> Array[@model.Observation] raise {
  let store = @incr_next.Store::Store()
  let region = store.region()
  let trigger = region.source(0)
  let query : (Unit) -> CutoffValue raise @incr_next.ReadError = match
    script.kind() {
    @model.CutoffKind::AlwaysChangedEquivalent => {
      let query = region.query((ctx, _unit : Unit) => {
        let step = ctx.get(trigger.view())
        CutoffValue::{ value: 0, marker: step }
      })
      unit => store.get(query.view(unit))
    }
    @model.CutoffKind::EqEquivalent => {
      let query = region.query(
        (ctx, _unit : Unit) => {
          let step = ctx.get(trigger.view())
          CutoffValue::{ value: 0, marker: step }
        },
        cutoff=@incr_next.Cutoff::equal(),
      )
      unit => store.get(query.view(unit))
    }
    @model.CutoffKind::ConsecutiveEquivalent => {
      let query = region.query(
        (ctx, _unit : Unit) => {
          let step = ctx.get(trigger.view())
          CutoffValue::{ value: 0, marker: step }
        },
        cutoff=@incr_next.Cutoff::type_owned(),
      )
      unit => store.get(query.view(unit))
    }
    @model.CutoffKind::EqChanged => {
      let query = region.query(
        (ctx, _unit : Unit) => {
          let step = ctx.get(trigger.view())
          CutoffValue::{ value: step, marker: step }
        },
        cutoff=@incr_next.Cutoff::equal(),
      )
      unit => store.get(query.view(unit))
    }
    @model.CutoffKind::TypeOwnedEquivalent
    | @model.CutoffKind::TypeOwnedChanged => {
      let kind = script.kind()
      let query = region.query(
        (ctx, _unit : Unit) => {
          let step = ctx.get(trigger.view())
          CutoffValue::{
            value: cutoff_observation_value(kind, step),
            marker: step,
          }
        },
        cutoff=@incr_next.Cutoff::type_owned(),
      )
      unit => store.get(query.view(unit))
    }
    @model.CutoffKind::DynamicEquivalent => {
      let old_branch = region.source(0)
      let new_branch = region.source(0)
      let query = region.query(
        (ctx, _unit : Unit) => {
          let flag = ctx.get(trigger.view())
          let value = if flag == 0 {
            ctx.get(old_branch.view())
          } else {
            ctx.get(new_branch.view())
          }
          CutoffValue::{ value, marker: flag }
        },
        cutoff=@incr_next.Cutoff::equal(),
      )
      unit => store.get(query.view(unit))
    }
  }
  let observations : Array[@model.Observation] = []
  for step in script.steps() {
    let _ : Result[Unit, Unit] = store.transaction(tx => {
      tx.set(trigger, step)
      Ok(())
    })
    let value = query(()) catch {
      _ => abort("valid cutoff read failed unexpectedly")
    }
    observations.push(@model.Observation::Value(value.value))
    match script.kind() {
      @model.CutoffKind::TypeOwnedEquivalent
      | @model.CutoffKind::TypeOwnedChanged
      | @model.CutoffKind::ConsecutiveEquivalent =>
        observations.push(@model.Observation::Marker(value.marker))
      _ => ()
    }
  }
  ignore(region.close())
  observations
}
