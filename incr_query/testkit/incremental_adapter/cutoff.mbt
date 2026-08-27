///|
priv struct CutoffValue {
  value : Int
}

///|
impl Eq for CutoffValue with fn equal(self, other) {
  self.value == other.value
}

///|
/// Runs the same supported cutoff workload against the incremental kernel.
pub fn evaluate_cutoff(
  script : @model.CutoffScript,
) -> Array[@model.Observation] raise {
  let store = @incr_query.Store::Store()
  let region = store.region()
  let trigger = region.source(0)
  let query : (Unit) -> CutoffValue raise @incr_query.ReadError = match
    script.kind() {
    @model.CutoffKind::AlwaysChangedEquivalent => {
      let query = region.query((ctx, _unit : Unit) => {
        ignore(ctx.get(trigger.view()))
        CutoffValue::{ value: 0 }
      })
      unit => store.get(query.view(unit))
    }
    @model.CutoffKind::EqEquivalent => {
      let query = region.query(
        (ctx, _unit : Unit) => {
          ignore(ctx.get(trigger.view()))
          CutoffValue::{ value: 0 }
        },
        cutoff=@incr_query.Cutoff::equal(),
      )
      unit => store.get(query.view(unit))
    }
    @model.CutoffKind::EqChanged => {
      let query = region.query(
        (ctx, _unit : Unit) => {
          let step = ctx.get(trigger.view())
          CutoffValue::{ value: step }
        },
        cutoff=@incr_query.Cutoff::equal(),
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
          CutoffValue::{ value, }
        },
        cutoff=@incr_query.Cutoff::equal(),
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
  }
  ignore(region.close())
  observations
}
