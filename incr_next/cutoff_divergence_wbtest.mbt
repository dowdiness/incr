///|
priv struct GenerationValue {
  semantic : Int
  generation : Int
}

///|
impl Eq for GenerationValue with fn equal(self, other) {
  self.semantic == other.semantic
}

///|
priv struct NearValue {
  value : Int
}

///|
impl CutoffEq for NearValue with fn cutoff_equal(self, other) {
  let distance = self.value - other.value
  distance >= -1 && distance <= 1
}

///|
test "custom Eq can leave a downstream generation stale" {
  let store = Store::Store()
  let region = store.region().unwrap()
  let trigger = region.source(0).unwrap()
  let target = region
    .query_eq((ctx, _unit : Unit) => {
      match ctx.read(trigger.view()) {
        Ok(generation) => Ok(GenerationValue::{ semantic: 7, generation })
        Err(error) => Err(error)
      }
    })
    .unwrap()
  let downstream = region
    .query((ctx, _unit : Unit) => {
      ctx.read(target.at(())).map(value => value.generation)
    })
    .unwrap()
  assert_eq(store.read(target.at(())).unwrap().generation, 0)
  assert_eq(store.read(downstream.at(())), Ok(0))
  let old_changed_at = target.core.memo.get(()).unwrap().changed_at
  ignore(store.transaction(tx => tx.set(trigger, 1)))
  assert_eq(store.read(downstream.at(())), Ok(0))
  let direct = store.read(target.at(())).unwrap()
  assert_eq(direct.generation, 1)
  assert_eq(target.core.memo.get(()).unwrap().changed_at, old_changed_at)
  assert_eq(target.core.cutoff_count.val, 1)
  assert_eq(downstream.core.compute_count.val, 1)
  ignore(region.close())
}

///|
test "non-transitive local nearness leaves downstream at zero" {
  let store = Store::Store()
  let region = store.region().unwrap()
  let trigger = region.source(0).unwrap()
  let target = region
    .query_type_owned((ctx, _unit : Unit) => {
      ctx.read(trigger.view()).map(value => NearValue::{ value, })
    })
    .unwrap()
  let downstream = region
    .query((ctx, _unit : Unit) => {
      ctx.read(target.at(())).map(value => value.value)
    })
    .unwrap()
  assert_eq(store.read(downstream.at(())), Ok(0))
  ignore(store.transaction(tx => tx.set(trigger, 1)))
  assert_eq(store.read(downstream.at(())), Ok(0))
  ignore(store.transaction(tx => tx.set(trigger, 2)))
  assert_eq(store.read(downstream.at(())), Ok(0))
  assert_eq(store.read(target.at(())).unwrap().value, 2)
  assert_eq(target.core.cutoff_count.val, 2)
  assert_eq(downstream.core.compute_count.val, 1)
  ignore(region.close())
}
