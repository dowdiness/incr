///|
test "evaluation phase rejects root reads and Region mutation globally" {
  let store = Store::Store()
  let region = store.region().unwrap()
  let other = Store::Store()
  let other_region = other.region().unwrap()
  let other_source = other_region.source(9).unwrap()
  let root_error = Ref(None)
  let region_error = Ref(None)
  let query = region
    .query((ctx, _unit : Unit) => {
      root_error.val = Some(other.read(other_source.view()))
      region_error.val = Some(other.region())
      match ctx.revision().value() {
        0 => Ok(1)
        revision => Ok(revision)
      }
    })
    .unwrap()
  assert_eq(store.read(query.at(())), Ok(1))
  assert_true(root_error.val.unwrap() is Err(ReadError::ReentrantRootRead(..)))
  assert_true(
    region_error.val.unwrap() is Err(RegionError::MutationDuringEvaluation(..)),
  )
}

///|
test "phase is restored after catchable root rejection" {
  let store = Store::Store()
  let region = store.region().unwrap()
  let source = region.source(3).unwrap()
  let query = region
    .query((ctx, _unit : Unit) => {
      match ctx.read(source.view()) {
        Ok(value) => Ok(value)
        Err(error) => Err(error)
      }
    })
    .unwrap()
  let first = store.read(query.at(()))
  let second = store.read(source.view())
  assert_eq(first, Ok(3))
  assert_eq(second, Ok(3))
}
