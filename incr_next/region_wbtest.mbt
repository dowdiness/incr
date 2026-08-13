///|
test "Region close changes only ChangeEpoch and invalidates surviving Views" {
  let store = Store::Store()
  let region = store.region().unwrap()
  let source = region.source(11).unwrap()
  let query = region
    .query((ctx, _unit : Unit) => ctx.read(source.view()))
    .unwrap()
  let source_view = source.view()
  let query_view = query.at(())
  assert_eq(store.read(query_view), Ok(11))
  let revision_before = store.revision().value()
  let close_epoch_before = store.change_epoch.val
  assert_true(region.close() is Ok(_))
  assert_eq(store.revision().value(), revision_before)
  assert_eq(store.change_epoch.val, close_epoch_before + 1)
  assert_true(store.read(source_view) is Err(ReadError::ClosedRegion(..)))
  assert_true(store.read(query_view) is Err(ReadError::ClosedRegion(..)))
  assert_true(region.close() is Err(RegionError::ClosedRegion(..)))
  assert_eq(store.change_epoch.val, close_epoch_before + 1)
}

///|
test "sibling Regions remain independent after one closes" {
  let store = Store::Store()
  let first = store.region().unwrap()
  let second = store.region().unwrap()
  let first_source = first.source(1).unwrap()
  let second_source = second.source(2).unwrap()
  let first_view = first_source.view()
  assert_true(first.close() is Ok(_))
  assert_true(store.read(first_view) is Err(ReadError::ClosedRegion(..)))
  assert_eq(store.read(second_source.view()), Ok(2))
  assert_true(second.source(3) is Ok(_))
}

///|
test "cross Region Source failure is visible to a surviving query View" {
  let store = Store::Store()
  let owner = store.region().unwrap()
  let dependent = store.region().unwrap()
  let source = owner.source(12).unwrap()
  let source_generation = owner.generation()
  let view = source.view()
  let query = dependent.query((ctx, _unit : Unit) => ctx.read(view)).unwrap()
  let query_view = query.at(())
  assert_eq(store.read(query_view), Ok(12))
  assert_true(owner.close() is Ok(_))
  assert_true(store.read(query_view) is Err(ReadError::ClosedRegion(..)))
  assert_eq(
    store.read(query_view),
    Err(ReadError::ClosedRegion(generation=source_generation)),
  )
  assert_true(dependent.source(13) is Ok(_))
}
