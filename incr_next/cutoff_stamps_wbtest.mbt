///|
priv struct SemanticStamp {
  value : Int
  marker : Int
}

///|
impl CutoffEq for SemanticStamp with fn cutoff_equal(self, other) {
  self.value == other.value
}

///|
test "Eq changed preserves identity and advances both stamps" {
  let store = Store::Store()
  let region = store.region().unwrap()
  let trigger = region.source(0).unwrap()
  let query = region
    .query_eq((ctx, _unit : Unit) => ctx.read(trigger.view()))
    .unwrap()
  assert_eq(store.read(query.at(())), Ok(0))
  let before = query.core.memo.get(()).unwrap()
  ignore(store.transaction(tx => tx.set(trigger, 1)))
  let current = store.change_epoch.val
  assert_eq(store.read(query.at(())), Ok(1))
  let after = query.core.memo.get(()).unwrap()
  assert_eq(after.memo_id, before.memo_id)
  assert_eq(after.value, 1)
  assert_eq(after.verified_at, current)
  assert_eq(after.changed_at, current)
  assert_eq(query.core.cutoff_count.val, 1)
  ignore(region.close())
}

///|
test "type-owned equivalent keeps semantic value and changed stamp but refreshes marker" {
  let store = Store::Store()
  let region = store.region().unwrap()
  let trigger = region.source(0).unwrap()
  let computes = Ref(0)
  let query = region
    .query_type_owned((ctx, _unit : Unit) => {
      computes.val = computes.val + 1
      match ctx.read(trigger.view()) {
        Ok(marker) => Ok(SemanticStamp::{ value: 7, marker })
        Err(error) => Err(error)
      }
    })
    .unwrap()
  assert_eq(store.read(query.at(())).unwrap().marker, 0)
  let before = query.core.memo.get(()).unwrap()
  ignore(store.transaction(tx => tx.set(trigger, 1)))
  let current = store.change_epoch.val
  let direct = store.read(query.at(())).unwrap()
  let after = query.core.memo.get(()).unwrap()
  assert_eq(direct.marker, 1)
  assert_eq(after.value.marker, 1)
  assert_eq(after.memo_id, before.memo_id)
  assert_eq(after.verified_at, current)
  assert_eq(after.changed_at, before.changed_at)
  assert_eq(query.core.cutoff_count.val, 1)
  assert_eq(computes.val, 2)
  ignore(region.close())
}

///|
test "type-owned changed advances identity stamps while retaining memo id" {
  let store = Store::Store()
  let region = store.region().unwrap()
  let trigger = region.source(0).unwrap()
  let query = region
    .query_type_owned((ctx, _unit : Unit) => {
      match ctx.read(trigger.view()) {
        Ok(value) => Ok(SemanticStamp::{ value, marker: value })
        Err(error) => Err(error)
      }
    })
    .unwrap()
  assert_eq(store.read(query.at(())).unwrap().value, 0)
  let before = query.core.memo.get(()).unwrap()
  ignore(store.transaction(tx => tx.set(trigger, 1)))
  let current = store.change_epoch.val
  assert_eq(store.read(query.at(())).unwrap().value, 1)
  let after = query.core.memo.get(()).unwrap()
  assert_eq(after.memo_id, before.memo_id)
  assert_eq(after.verified_at, current)
  assert_eq(after.changed_at, current)
  assert_eq(query.core.cutoff_count.val, 1)
  ignore(region.close())
}
