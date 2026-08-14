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
  assert_eq(shared.core.memo.get((0, 0)).unwrap().trace.map(dep => dep.kind), [
    Source,
  ])
  assert_eq(left.core.memo.get(()).unwrap().trace.map(dep => dep.kind), [Query])
  assert_eq(right.core.memo.get(()).unwrap().trace.map(dep => dep.kind), [Query])
  assert_eq(root.core.memo.get(()).unwrap().trace.map(dep => dep.kind), [
    Query,
    Query,
  ])
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
test "successful memos own direct Source Query and Revision traces" {
  let store = Store::Store()
  let region = store.region().unwrap()
  let source = region.source(1).unwrap()
  let source_query = region
    .query((ctx, _unit : Unit) => ctx.read(source.view()))
    .unwrap()
  let revision_query = region
    .query((ctx, _unit : Unit) => {
      match ctx.revision() {
        Ok(_) => Ok(2)
        Err(error) => Err(error)
      }
    })
    .unwrap()
  let child_query = region
    .query((ctx, _unit : Unit) => ctx.read(source_query.at(())))
    .unwrap()
  let root_query = region
    .query((ctx, _unit : Unit) => {
      match (ctx.read(child_query.at(())), ctx.read(revision_query.at(()))) {
        (Ok(left), Ok(right)) => Ok(left + right)
        (Err(error), _) => Err(error)
        (_, Err(error)) => Err(error)
      }
    })
    .unwrap()
  assert_eq(store.read(source_query.at(())), Ok(1))
  assert_eq(store.read(revision_query.at(())), Ok(2))
  assert_eq(store.read(child_query.at(())), Ok(1))
  assert_eq(store.read(root_query.at(())), Ok(3))
  assert_eq(
    source_query.core.memo.get(()).unwrap().trace.map(dep => dep.kind),
    [Source],
  )
  assert_eq(
    revision_query.core.memo.get(()).unwrap().trace.map(dep => dep.kind),
    [Revision],
  )
  assert_eq(child_query.core.memo.get(()).unwrap().trace.map(dep => dep.kind), [
    Query,
  ])
  assert_eq(root_query.core.memo.get(()).unwrap().trace.map(dep => dep.kind), [
    Query,
    Query,
  ])
}

///|
test "failed recompute releases its temporary trace" {
  let store = Store::Store()
  let region = store.region().unwrap()
  let source = region.source(1).unwrap()
  let captured = Ref(None)
  let query = region
    .query((ctx, _unit : Unit) => {
      captured.val = Some(ctx)
      let outcome : Result[Unit, ReadError] = match ctx.read(source.view()) {
        Ok(_) => Err(ReadError::ExpiredQueryContext)
        Err(error) => Err(error)
      }
      outcome
    })
    .unwrap()
  assert_eq(store.read(query.at(())), Err(ReadError::ExpiredQueryContext))
  assert_true(captured.val.unwrap().frame.val is None)
  assert_true(query.core.memo.is_empty())
}

///|
test "Region close clears Query memo state" {
  let store = Store::Store()
  let region = store.region().unwrap()
  let source = region.source(4).unwrap()
  let query = region
    .query((ctx, _key : Int) => ctx.read(source.view()))
    .unwrap()
  assert_eq(store.read(query.at(4)), Ok(4))
  assert_eq(query.core.memo.length(), 1)
  assert_eq(query.core.memo.get(4).unwrap().trace.length(), 1)
  assert_true(query.core.compute.val is Some(_))
  ignore(region.close())
  assert_true(query.core.memo.is_empty())
  assert_true(query.core.compute.val is None)
}
