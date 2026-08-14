///|
test "a shared diamond has one inner kernel computation" {
  let store = Store::Store()
  let region = store.region().unwrap()
  let source = region.source(0).unwrap()
  let shared = region
    .query((ctx, _key : (Int, Int)) => ctx.read(source.view()))
    .unwrap()
  let left = region
    .query((ctx, _unit : Unit) => {
      match ctx.read(shared.at((0, 0))) {
        Ok(value) => Ok(value + 1)
        Err(error) => Err(error)
      }
    })
    .unwrap()
  let right = region
    .query((ctx, _unit : Unit) => {
      match ctx.read(shared.at((0, 0))) {
        Ok(value) => Ok(value + 2)
        Err(error) => Err(error)
      }
    })
    .unwrap()
  let root = region
    .query((ctx, _unit : Unit) => {
      match (ctx.read(left.at(())), ctx.read(right.at(()))) {
        (Ok(a), Ok(b)) => Ok(a + b)
        (Err(error), _) => Err(error)
        (_, Err(error)) => Err(error)
      }
    })
    .unwrap()
  assert_eq(store.read(root.at(())), Ok(3))
  assert_eq(root.core.compute_count.val, 1)
  assert_eq(left.core.compute_count.val, 1)
  assert_eq(right.core.compute_count.val, 1)
  assert_eq(shared.core.compute_count.val, 1)
  assert_eq(shared.core.cache_hit_count.val, 1)
  assert_eq(shared.core.memo.length(), 1)
  assert_eq(store.read(root.at(())), Ok(3))
  assert_eq(root.core.compute_count.val, 1)
  assert_eq(shared.core.compute_count.val, 1)
  assert_eq(shared.core.cache_hit_count.val, 1)
}

///|
test "memo hits, identity, and epoch stamps are white-box observable" {
  let store = Store::Store()
  let region = store.region().unwrap()
  let source = region.source(2).unwrap()
  let query = region
    .query((ctx, _key : Int) => ctx.read(source.view()))
    .unwrap()
  assert_eq(store.read(query.at(7)), Ok(2))
  assert_eq(query.core.memo.length(), 1)
  assert_eq(query.core.compute_count.val, 1)
  assert_eq(query.core.cache_hit_count.val, 0)
  let before = query.core.memo.get(7).unwrap()
  assert_eq(before.verified_at, store.change_epoch.val)
  assert_eq(before.changed_at, store.change_epoch.val)
  assert_eq(store.read(query.at(7)), Ok(2))
  assert_eq(query.core.compute_count.val, 1)
  assert_eq(query.core.cache_hit_count.val, 1)
  let memo_id = query.core.memo.get(7).unwrap().memo_id
  ignore(store.transaction(tx => tx.set(source, 3)))
  let current_epoch = store.change_epoch.val
  assert_eq(store.read(query.at(7)), Ok(3))
  let after = query.core.memo.get(7).unwrap()
  assert_eq(query.core.compute_count.val, 2)
  assert_eq(query.core.cache_hit_count.val, 1)
  assert_eq(after.memo_id, memo_id)
  assert_true(after.verified_at > before.verified_at)
  assert_true(after.changed_at > before.changed_at)
  assert_eq(after.verified_at, current_epoch)
  assert_eq(after.changed_at, current_epoch)
}

///|
test "Region close clears Query memo state" {
  let store = Store::Store()
  let region = store.region().unwrap()
  let query = region.query((_ctx, key : Int) => Ok(key + 1)).unwrap()
  assert_eq(store.read(query.at(4)), Ok(5))
  assert_eq(query.core.memo.length(), 1)
  assert_true(query.core.compute.val is Some(_))
  ignore(region.close())
  assert_true(query.core.memo.is_empty())
  assert_true(query.core.compute.val is None)
}
