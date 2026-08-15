///|
struct OwnedValue {
  value : Int
  marker : Int
}

///|
impl CutoffEq for OwnedValue with fn cutoff_equal(self, other) {
  self.value == other.value
}

///|
test "typed constructors preserve newest values and fixed cutoff work" {
  let store = Store::Store()
  let region = store.region().unwrap()
  let trigger = region.source(0).unwrap()
  let always_runs = Ref(0)
  let always = region
    .query_always_changed((ctx, _unit : Unit) => {
      always_runs.val = always_runs.val + 1
      match ctx.read(trigger.view()) {
        Ok(_) => Ok(7)
        Err(error) => Err(error)
      }
    })
    .unwrap()
  assert_eq(store.read(always.at(())), Ok(7))
  let always_id = always.core.memo.get(()).unwrap().memo_id
  ignore(store.transaction(tx => tx.set(trigger, 1)))
  assert_eq(store.read(always.at(())), Ok(7))
  assert_eq(always_runs.val, 2)
  assert_eq(always.core.cutoff_count.val, 1)
  assert_eq(always.core.memo.get(()).unwrap().memo_id, always_id)
  assert_eq(
    always.core.memo.get(()).unwrap().changed_at,
    store.change_epoch.val,
  )

  let eq = region
    .query_eq((ctx, _unit : Unit) => {
      match ctx.read(trigger.view()) {
        Ok(_) => Ok(7)
        Err(error) => Err(error)
      }
    })
    .unwrap()
  assert_eq(store.read(eq.at(())).unwrap(), 7)
  let eq_before = eq.core.memo.get(()).unwrap()
  ignore(store.transaction(tx => tx.set(trigger, 2)))
  assert_eq(store.read(eq.at(())).unwrap(), 7)
  let eq_after = eq.core.memo.get(()).unwrap()
  assert_eq(eq.core.cutoff_count.val, 1)
  assert_eq(eq_after.value, 7)
  assert_eq(eq_after.memo_id, eq_before.memo_id)
  assert_eq(eq_after.changed_at, eq_before.changed_at)
  assert_eq(eq_after.verified_at, store.change_epoch.val)

  let owned_runs = Ref(0)
  let owned = region
    .query_type_owned((ctx, _unit : Unit) => {
      owned_runs.val = owned_runs.val + 1
      match ctx.read(trigger.view()) {
        Ok(_) => Ok(OwnedValue::{ value: 3, marker: store.change_epoch.val })
        Err(error) => Err(error)
      }
    })
    .unwrap()
  let initial_owned = store.read(owned.at(())).unwrap()
  assert_eq(initial_owned.value, 3)
  assert_eq(initial_owned.marker, 2)
  let owned_before = owned.core.memo.get(()).unwrap()
  ignore(store.transaction(tx => tx.set(trigger, 3)))
  let newest = store.read(owned.at(())).unwrap()
  assert_eq(newest.marker, 3)
  let owned_after = owned.core.memo.get(()).unwrap()
  assert_eq(owned.core.cutoff_count.val, 1)
  assert_eq(owned_after.value.marker, 3)
  assert_eq(owned_after.memo_id, owned_before.memo_id)
  assert_eq(owned_after.changed_at, owned_before.changed_at)
  assert_eq(owned_after.verified_at, store.change_epoch.val)
  assert_eq(owned_runs.val, 2)
  ignore(region.close())
  assert_true(owned.core.cutoff.val is AlwaysChanged)
}

///|
test "equivalent cutoff keeps newest trace and skips a downstream query" {
  let store = Store::Store()
  let region = store.region().unwrap()
  let branch = region.source(0).unwrap()
  let old_branch = region.source(4).unwrap()
  let new_branch = region.source(4).unwrap()
  let root = region
    .query_eq((ctx, _unit : Unit) => {
      match ctx.read(branch.view()) {
        Ok(flag) =>
          if flag == 0 {
            ctx.read(old_branch.view())
          } else {
            ctx.read(new_branch.view())
          }
        Err(error) => Err(error)
      }
    })
    .unwrap()
  let downstream_runs = Ref(0)
  let downstream = region
    .query((ctx, _unit : Unit) => {
      downstream_runs.val = downstream_runs.val + 1
      ctx.read(root.at(())).map(value => value + 1)
    })
    .unwrap()
  assert_eq(store.read(downstream.at(())), Ok(5))
  assert_eq(root.core.compute_count.val, 1)
  assert_eq(downstream.core.compute_count.val, 1)
  let old_changed_at = root.core.memo.get(()).unwrap().changed_at
  ignore(store.transaction(tx => tx.set(branch, 1)))
  assert_eq(store.read(downstream.at(())), Ok(5))
  assert_eq(root.core.compute_count.val, 2)
  assert_eq(root.core.cutoff_count.val, 1)
  assert_eq(root.core.memo.get(()).unwrap().changed_at, old_changed_at)
  assert_eq(downstream.core.compute_count.val, 1)
  ignore(store.transaction(tx => tx.set(old_branch, 12)))
  assert_eq(store.read(downstream.at(())), Ok(5))
  assert_eq(root.core.compute_count.val, 2)
  assert_eq(root.core.verification_count.val, 2)
  assert_eq(root.core.green_count.val, 1)
  assert_eq(root.core.cutoff_count.val, 1)
  assert_eq(downstream.core.compute_count.val, 1)
  ignore(store.transaction(tx => tx.set(branch, 0)))
  assert_eq(store.read(downstream.at(())), Ok(13))
  assert_eq(root.core.compute_count.val, 3)
  assert_eq(root.core.cutoff_count.val, 2)
  assert_eq(downstream.core.compute_count.val, 2)
  assert_eq(downstream_runs.val, 2)
}

///|
test "consecutive equivalent reads expose newest markers with stable change stamp" {
  let store = Store::Store()
  let region = store.region().unwrap()
  let trigger = region.source(0).unwrap()
  let computes = Ref(0)
  let query = region
    .query_type_owned((ctx, _unit : Unit) => {
      computes.val = computes.val + 1
      match ctx.read(trigger.view()) {
        Ok(marker) => Ok(OwnedValue::{ value: 9, marker })
        Err(error) => Err(error)
      }
    })
    .unwrap()
  let first = store.read(query.at(())).unwrap()
  let changed_at = query.core.memo.get(()).unwrap().changed_at
  ignore(store.transaction(tx => tx.set(trigger, 1)))
  let second = store.read(query.at(())).unwrap()
  ignore(store.transaction(tx => tx.set(trigger, 2)))
  let third = store.read(query.at(())).unwrap()
  let memo = query.core.memo.get(()).unwrap()
  assert_eq(first.marker, 0)
  assert_eq(second.marker, 1)
  assert_eq(third.marker, 2)
  assert_eq(computes.val, 3)
  assert_eq(query.core.cutoff_count.val, 2)
  assert_eq(memo.value.marker, 2)
  assert_eq(memo.changed_at, changed_at)
  assert_eq(memo.verified_at, store.change_epoch.val)
  ignore(region.close())
}
